// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VerifierRegistryModuleV1} from "../src/VerifierRegistryModuleV1.sol";
import {BountyFundingModuleV1} from "../src/BountyFundingModuleV1.sol";
import {BountySubmissionModuleV1} from "../src/BountySubmissionModuleV1.sol";

interface VmVerifierV1 {
    function prank(address account) external;
    function deal(address account, uint256 newBalance) external;
    function chainId(uint256 newId) external;
    function warp(uint256 timestamp) external;
}

/** Foundry-only harness. Funding and fake GitHub review are NOT deployable. */
contract VerifierRegistryHarness is VerifierRegistryModuleV1 {
    address private immutable testController;

    constructor(uint256 chainId, address governance)
        VerifierRegistryModuleV1(chainId, governance)
    {
        testController = msg.sender;
    }

    function testFund(FundingRequest calldata terms) external payable returns (uint256) {
        return _recordFunding(terms);
    }

    function testAuthorizeRetry(uint256 bounty, uint64 attempt, bytes32 reportDigest) external {
        require(msg.sender == testController, "test controller only");
        _authorizeRetryFromReview(bounty, attempt, reportDigest);
    }
}

contract VerifierRegistryModuleV1Test {
    VmVerifierV1 constant vm = VmVerifierV1(
        address(uint160(uint256(keccak256("hevm cheat code"))))
    );
    uint256 constant CHAIN = 31337;
    address constant SPONSOR = address(0xA110);
    address constant DEV = address(0xCAFE);
    address constant ARBITRATOR = address(0xA4B);
    address constant C1 = address(0xC111);
    address constant C2 = address(0xC222);
    address constant S1 = address(0x5101);
    address constant S2 = address(0x5202);
    address constant S3 = address(0x5303);
    address constant ATTACKER = address(0xBAD);
    bytes32 constant ORG1 = keccak256("legal-verifier-org-alpha");
    bytes32 constant ORG2 = keccak256("legal-verifier-org-beta");
    bytes20 constant BASE = hex"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    bytes20 constant HEAD = hex"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

    VerifierRegistryHarness private escrow;

    function setUp() public {
        vm.chainId(CHAIN);
        vm.warp(1780000000);
        vm.deal(SPONSOR, 100 ether);
        escrow = new VerifierRegistryHarness(CHAIN, address(this));
    }

    function _sortedRoster(bytes32 a, bytes32 b)
        internal pure returns (bytes32[] memory list)
    {
        require(a != b && a != bytes32(0) && b != bytes32(0), "bad fixture org");
        list = new bytes32[](2);
        (list[0], list[1]) = a < b ? (a, b) : (b, a);
    }

    function _fundFor(bytes32 a, bytes32 b) internal returns (uint256 bounty) {
        bytes32[] memory roster = _sortedRoster(a, b);
        BountyFundingModuleV1.FundingRequest memory request =
            BountyFundingModuleV1.FundingRequest({
                repositoryId: 56789,
                baselineGitSha: BASE,
                manifestDigest: bytes32(uint256(10)),
                verifierPolicyDigest: sha256(
                    abi.encode("CertiFiks:verifier-roster:v1", uint8(2), roster)
                ),
                disputePolicyDigest: bytes32(uint256(12)),
                primaryArbitrator: ARBITRATOR,
                submissionDeadline: uint64(block.timestamp + 8 days),
                verificationSeconds: 2 days,
                challengeSeconds: 1 days,
                arbitrationSeconds: 2 days,
                assetKind: 0
            });
        vm.prank(SPONSOR);
        bounty = escrow.testFund{value: 1 ether}(request);
        vm.prank(SPONSOR);
        escrow.registerCommittedReviewerRoster(bounty, roster, 2);
    }

    function _fund() internal returns (uint256 bounty) {
        return _fundFor(ORG1, ORG2);
    }

    function _candidate() internal pure returns (BountySubmissionModuleV1.Candidate memory) {
        return BountySubmissionModuleV1.Candidate({
            repositoryId: 56789,
            pullNumber: 23,
            baseGitSha: BASE,
            headGitSha: HEAD,
            imageDigest: bytes32(uint256(20)),
            evidenceDigest: bytes32(uint256(21)),
            manifestDigest: bytes32(uint256(10)),
            manifestVersion: 1
        });
    }

    function _submitted() internal returns (uint256 bounty) {
        return _submittedFor(ORG1, ORG2);
    }

    function _submittedFor(bytes32 orgA, bytes32 orgB) internal returns (uint256 bounty) {
        bounty = _fundFor(orgA, orgB);
        vm.prank(DEV);
        escrow.applyForBounty(bounty);
        vm.prank(SPONSOR);
        escrow.offerAssignment(bounty, DEV);
        vm.prank(DEV);
        escrow.acceptAssignment(bounty);
        vm.prank(DEV);
        escrow.submitCandidate(bounty, _candidate());
    }

    function _enroll(bytes32 org, address controller, address signer) internal {
        escrow.enrollReviewerOrganization(
            org, controller, signer, keccak256("business identity dossier"),
            keccak256("test capability profile"), keccak256("conflict disclosure")
        );
    }

    function _activate(bytes32 org, address controller) internal {
        vm.prank(controller);
        escrow.activateReviewerOrganization(org);
    }

    function _admitBoth() internal {
        _enroll(ORG1, C1, S1);
        _activate(ORG1, C1);
        _enroll(ORG2, C2, S2);
        _activate(ORG2, C2);
    }

    function _assignBoth(uint256 bounty) internal {
        escrow.assignReviewerJob(bounty, ORG1);
        escrow.assignReviewerJob(bounty, ORG2);
    }

    function _revertAs(address who, bytes memory data) internal {
        vm.prank(who);
        (bool ok,) = address(escrow).call(data);
        require(!ok, "invalid reviewer operation succeeded");
    }

    function testApprovedTwoOrganizationsCanAcceptAndDeclareOnOneAttempt() public {
        _admitBoth();
        uint256 bounty = _submitted();
        _assignBoth(bounty);
        vm.prank(S1);
        escrow.acceptReviewerJob(bounty, 1, ORG1);
        vm.prank(S2);
        escrow.acceptReviewerJob(bounty, 1, ORG2);
        vm.prank(S1);
        escrow.declareReviewerEvidence(bounty, 1, ORG1, bytes32(uint256(201)));
        vm.prank(S2);
        escrow.declareReviewerEvidence(bounty, 1, ORG2, bytes32(uint256(202)));
        VerifierRegistryModuleV1.ReviewerJob memory a = escrow.getReviewerJob(bounty, 1, ORG1);
        VerifierRegistryModuleV1.ReviewerJob memory b = escrow.getReviewerJob(bounty, 1, ORG2);
        require(a.accepted && b.accepted, "approval not recorded");
        require(a.declaredReportDigest != b.declaredReportDigest, "reports not distinct");
        require(a.attemptDigest == b.attemptDigest, "different target attempt");
        require(escrow.getReviewerOrganization(ORG1).declaredEvidenceCount == 1, "bad activity counter");
        require(escrow.reviewerJobCount(bounty, 1) == 2, "orgs not independently counted");
        require(address(escrow).balance == escrow.totalReservedAtoms(), "funds moved by report");
    }

    function testUnapprovedOrInactiveCannotAcceptReview() public {
        _enroll(ORG1, C1, S1);
        uint256 bounty = _submitted();
        _revertAs(address(this), abi.encodeWithSelector(escrow.assignReviewerJob.selector, bounty, ORG1));
        _activate(ORG1, C1);
        escrow.assignReviewerJob(bounty, ORG1);
        _revertAs(C1, abi.encodeWithSelector(escrow.acceptReviewerJob.selector, bounty, 1, ORG1));
        _revertAs(ATTACKER, abi.encodeWithSelector(escrow.acceptReviewerJob.selector, bounty, 1, ORG1));
        vm.prank(S1);
        escrow.acceptReviewerJob(bounty, 1, ORG1);
    }

    function testGovernanceAdmissionAndControllerAcceptanceCannotBeForged() public {
        _revertAs(ATTACKER, abi.encodeWithSelector(
            escrow.enrollReviewerOrganization.selector,
            ORG1, C1, S1, bytes32(uint256(1)), bytes32(uint256(2)), bytes32(uint256(3))
        ));
        _enroll(ORG1, C1, S1);
        _revertAs(ATTACKER, abi.encodeWithSelector(escrow.activateReviewerOrganization.selector, ORG1));
        _revertAs(address(this), abi.encodeWithSelector(
            escrow.enrollReviewerOrganization.selector,
            ORG1, C1, S1, bytes32(uint256(1)), bytes32(uint256(2)), bytes32(uint256(3))
        ));
        _activate(ORG1, C1);
        require(escrow.getReviewerOrganization(ORG1).active, "controller activation missing");
    }

    function testCannotManufactureTwoOrganizationsWithAnotherSigningKey() public {
        _enroll(ORG1, C1, S1);
        _activate(ORG1, C1);
        _revertAs(address(this), abi.encodeWithSelector(
            escrow.enrollReviewerOrganization.selector,
            ORG2, C1, S3, bytes32(uint256(1)), bytes32(uint256(2)), bytes32(uint256(3))
        ));
        _revertAs(address(this), abi.encodeWithSelector(
            escrow.enrollReviewerOrganization.selector,
            ORG2, C2, S1, bytes32(uint256(1)), bytes32(uint256(2)), bytes32(uint256(3))
        ));
        require(escrow.walletOrganization(C1) == ORG1, "controller not pinned");
        require(escrow.walletOrganization(S1) == ORG1, "signer not pinned");
    }

    function testBountySponsorCannotBeOrganizationSignerOrController() public {
        bytes32 signerOrg = keccak256("sponsor-is-verifier-key");
        _enroll(signerOrg, C1, SPONSOR);
        _activate(signerOrg, C1);
        uint256 bounty = _submittedFor(signerOrg, ORG1);
        _revertAs(address(this), abi.encodeWithSelector(
            escrow.assignReviewerJob.selector, bounty, signerOrg
        ));
        // A wallet enrolled in one org cannot later impersonate a second
        // org. Verify the controller conflict against a clean registry, too.
        escrow = new VerifierRegistryHarness(CHAIN, address(this));
        bytes32 controllerOrg = keccak256("sponsor-controls-verifier");
        _enroll(controllerOrg, SPONSOR, S3);
        _activate(controllerOrg, SPONSOR);
        uint256 secondBounty = _submittedFor(controllerOrg, ORG1);
        _revertAs(address(this), abi.encodeWithSelector(
            escrow.assignReviewerJob.selector, secondBounty, controllerOrg
        ));
    }

    function testBountyDeveloperAndArbitratorCannotBeVerifiers() public {
        bytes32 devOrg = keccak256("developer-verifier");
        _enroll(devOrg, C1, DEV);
        _activate(devOrg, C1);
        bytes32 arbOrg = keccak256("arbitrator-verifier");
        _enroll(arbOrg, ARBITRATOR, S2);
        _activate(arbOrg, ARBITRATOR);
        uint256 bounty = _submittedFor(devOrg, arbOrg);
        _revertAs(address(this), abi.encodeWithSelector(escrow.assignReviewerJob.selector, bounty, devOrg));
        _revertAs(address(this), abi.encodeWithSelector(escrow.assignReviewerJob.selector, bounty, arbOrg));
    }

    function testPriorKeyRotationDoesNotEraseConflictIdentity() public {
        _enroll(ORG1, C1, DEV);
        _activate(ORG1, C1);
        vm.prank(C1);
        escrow.proposeReviewerSigner(ORG1, S1);
        escrow.approveReviewerSignerRotation(ORG1);
        require(escrow.walletOrganization(DEV) == ORG1, "old wallet identity erased");
        uint256 bounty = _submitted();
        _revertAs(address(this), abi.encodeWithSelector(escrow.assignReviewerJob.selector, bounty, ORG1));
    }

    function testStaleKeyBlockedAndGovernanceCanRefreshUnacceptedJob() public {
        _enroll(ORG1, C1, S1);
        _activate(ORG1, C1);
        uint256 bounty = _submitted();
        escrow.assignReviewerJob(bounty, ORG1);
        vm.prank(C1);
        escrow.proposeReviewerSigner(ORG1, S3);
        escrow.approveReviewerSignerRotation(ORG1);
        _revertAs(S1, abi.encodeWithSelector(escrow.acceptReviewerJob.selector, bounty, 1, ORG1));
        escrow.refreshUnacceptedJob(bounty, 1, ORG1);
        _revertAs(S1, abi.encodeWithSelector(escrow.acceptReviewerJob.selector, bounty, 1, ORG1));
        vm.prank(S3);
        escrow.acceptReviewerJob(bounty, 1, ORG1);
        vm.prank(S3);
        escrow.declareReviewerEvidence(bounty, 1, ORG1, bytes32(uint256(1)));
        require(escrow.getReviewerJob(bounty, 1, ORG1).signerEpoch == 2, "rotation epoch missed");
    }

    function testRotationAfterCompletedDeclarationNeverRewritesHistory() public {
        _enroll(ORG1, C1, S1);
        _activate(ORG1, C1);
        uint256 bounty = _submitted();
        escrow.assignReviewerJob(bounty, ORG1);
        vm.prank(S1);
        escrow.acceptReviewerJob(bounty, 1, ORG1);
        vm.prank(S1);
        escrow.declareReviewerEvidence(bounty, 1, ORG1, bytes32(uint256(1234)));
        vm.prank(C1);
        escrow.proposeReviewerSigner(ORG1, S3);
        escrow.approveReviewerSignerRotation(ORG1);
        _revertAs(address(this), abi.encodeWithSelector(
            escrow.refreshUnacceptedJob.selector, bounty, 1, ORG1
        ));
        VerifierRegistryModuleV1.ReviewerJob memory snapshot = escrow.getReviewerJob(bounty, 1, ORG1);
        require(snapshot.assignedSigner == S1 && snapshot.signerEpoch == 1, "snapshot rewritten");
        require(snapshot.declaredReportDigest == bytes32(uint256(1234)), "signed history rewritten");
    }

    function testRevocationStopsNewSignaturesButDoesNotDeleteOldEvidence() public {
        _enroll(ORG1, C1, S1);
        _activate(ORG1, C1);
        uint256 bounty = _submitted();
        escrow.assignReviewerJob(bounty, ORG1);
        vm.prank(S1);
        escrow.acceptReviewerJob(bounty, 1, ORG1);
        vm.prank(S1);
        escrow.declareReviewerEvidence(bounty, 1, ORG1, bytes32(uint256(44)));
        escrow.revokeReviewerOrganization(ORG1);
        require(!escrow.getReviewerOrganization(ORG1).active, "revocation failed");
        require(escrow.getReviewerJob(bounty, 1, ORG1).declaredReportDigest == bytes32(uint256(44)), "history erased");
        _revertAs(C1, abi.encodeWithSelector(escrow.activateReviewerOrganization.selector, ORG1));
        _revertAs(address(this), abi.encodeWithSelector(escrow.assignReviewerJob.selector, bounty, ORG1));
    }

    function testRevocationBeforeDeclarationBlocksSignerForever() public {
        _enroll(ORG1, C1, S1);
        _activate(ORG1, C1);
        uint256 bounty = _submitted();
        escrow.assignReviewerJob(bounty, ORG1);
        vm.prank(S1);
        escrow.acceptReviewerJob(bounty, 1, ORG1);
        escrow.revokeReviewerOrganization(ORG1);
        _revertAs(S1, abi.encodeWithSelector(
            escrow.declareReviewerEvidence.selector, bounty, 1, ORG1, bytes32(uint256(7))
        ));
    }

    function testOnlyGovernanceCanAssignAndJobsCannotDuplicate() public {
        _admitBoth();
        uint256 bounty = _submitted();
        _revertAs(SPONSOR, abi.encodeWithSelector(escrow.assignReviewerJob.selector, bounty, ORG1));
        escrow.assignReviewerJob(bounty, ORG1);
        _revertAs(address(this), abi.encodeWithSelector(escrow.assignReviewerJob.selector, bounty, ORG1));
        require(escrow.reviewerJobCount(bounty, 1) == 1, "duplicate org counted");
    }

    function testOneReviewerCannotDeclareTwiceOrSignForAnotherOrg() public {
        _admitBoth();
        uint256 bounty = _submitted();
        _assignBoth(bounty);
        _revertAs(S1, abi.encodeWithSelector(
            escrow.declareReviewerEvidence.selector, bounty, 1, ORG1, bytes32(uint256(1))
        ));
        vm.prank(S1);
        escrow.acceptReviewerJob(bounty, 1, ORG1);
        _revertAs(S1, abi.encodeWithSelector(escrow.declareReviewerEvidence.selector, bounty, 1, ORG1, bytes32(0)));
        _revertAs(S1, abi.encodeWithSelector(escrow.acceptReviewerJob.selector, bounty, 1, ORG2));
        _revertAs(S1, abi.encodeWithSelector(
            escrow.declareReviewerEvidence.selector, bounty, 1, ORG2, bytes32(uint256(8))
        ));
        vm.prank(S1);
        escrow.declareReviewerEvidence(bounty, 1, ORG1, bytes32(uint256(1)));
        _revertAs(S1, abi.encodeWithSelector(
            escrow.declareReviewerEvidence.selector, bounty, 1, ORG1, bytes32(uint256(2))
        ));
    }

    function testJobsExpireByFundedVerificationWindow() public {
        _admitBoth();
        uint256 bounty = _submitted();
        escrow.assignReviewerJob(bounty, ORG1);
        uint64 end = escrow.getReviewerJob(bounty, 1, ORG1).deadline;
        vm.warp(end);
        _revertAs(S1, abi.encodeWithSelector(escrow.acceptReviewerJob.selector, bounty, 1, ORG1));
        _revertAs(address(this), abi.encodeWithSelector(escrow.refreshUnacceptedJob.selector, bounty, 1, ORG1));
        _revertAs(address(this), abi.encodeWithSelector(escrow.assignReviewerJob.selector, bounty, ORG2));
    }

    function testOldAttemptJobCannotDecideOnNewHeadOrNewReviewAttempt() public {
        _admitBoth();
        uint256 bounty = _submitted();
        escrow.assignReviewerJob(bounty, ORG1);
        vm.prank(S1);
        escrow.acceptReviewerJob(bounty, 1, ORG1);
        escrow.testAuthorizeRetry(bounty, 1, bytes32(uint256(70)));
        BountySubmissionModuleV1.Candidate memory candidate = _candidate();
        candidate.headGitSha = hex"cccccccccccccccccccccccccccccccccccccccc";
        vm.prank(DEV);
        escrow.resubmitCandidate(bounty, candidate);
        _revertAs(S1, abi.encodeWithSelector(
            escrow.declareReviewerEvidence.selector, bounty, 1, ORG1, bytes32(uint256(70))
        ));
        escrow.assignReviewerJob(bounty, ORG2);
        VerifierRegistryModuleV1.ReviewerJob memory job = escrow.getReviewerJob(bounty, 2, ORG2);
        require(job.attemptId == 2, "new revision not isolated");
        require(job.attemptDigest != escrow.getReviewerJob(bounty, 1, ORG1).attemptDigest,
            "review assigned stale head digest");
    }

    function testRegistryStatusDoesNotChangeFinancialLiability() public {
        _admitBoth();
        uint256 bounty = _submitted();
        _assignBoth(bounty);
        vm.prank(S1);
        escrow.acceptReviewerJob(bounty, 1, ORG1);
        vm.prank(S1);
        escrow.declareReviewerEvidence(bounty, 1, ORG1, bytes32(uint256(67)));
        escrow.revokeReviewerOrganization(ORG2);
        require(address(escrow).balance == 1 ether, "review moved sponsor funds");
        require(escrow.totalReservedAtoms() == 1 ether, "review minted a credit");
    }

    function testSponsorCannotChangePrecommittedRosterOrQuorum() public {
        uint256 bounty = _fund();
        bytes32[] memory roster = _sortedRoster(ORG1, ORG2);
        require(escrow.getReviewerRoster(bounty).configured, "policy unregistered");
        require(escrow.getReviewerRoster(bounty).quorum == 2, "unexpected quorum");
        bytes32 savedDigest = escrow.getReviewerRoster(bounty).policyDigest;
        _revertAs(ATTACKER, abi.encodeWithSelector(
            escrow.registerCommittedReviewerRoster.selector, bounty, roster, uint8(2)
        ));
        _revertAs(SPONSOR, abi.encodeWithSelector(
            escrow.registerCommittedReviewerRoster.selector, bounty, roster, uint8(2)
        ));
        require(escrow.getReviewerRoster(bounty).policyDigest == savedDigest, "policy rewritten");
    }

    function testGovernanceCannotAssignApprovedOrgOutsideFundedRoster() public {
        _admitBoth();
        bytes32 otherOrg = keccak256("org-not-on-funded-list");
        _enroll(otherOrg, address(0xC333), address(0x5304));
        _activate(otherOrg, address(0xC333));
        uint256 bounty = _submitted();
        _revertAs(address(this), abi.encodeWithSelector(
            escrow.assignReviewerJob.selector, bounty, otherOrg
        ));
        require(escrow.reviewerJobCount(bounty, 1) == 0, "unauthorized member counted");
    }

    function testFundingPolicyDigestRejectsChangedOrganizationSet() public {
        bytes32[] memory approved = _sortedRoster(ORG1, ORG2);
        BountyFundingModuleV1.FundingRequest memory request =
            BountyFundingModuleV1.FundingRequest({
                repositoryId: 56789,
                baselineGitSha: BASE,
                manifestDigest: bytes32(uint256(10)),
                verifierPolicyDigest: sha256(
                    abi.encode("CertiFiks:verifier-roster:v1", uint8(2), approved)
                ),
                disputePolicyDigest: bytes32(uint256(12)),
                primaryArbitrator: ARBITRATOR,
                submissionDeadline: uint64(block.timestamp + 8 days),
                verificationSeconds: 2 days,
                challengeSeconds: 1 days,
                arbitrationSeconds: 2 days,
                assetKind: 0
            });
        vm.prank(SPONSOR);
        uint256 bounty = escrow.testFund{value: 1 ether}(request);
        bytes32[] memory swapped = new bytes32[](2);
        swapped[0] = approved[1];
        swapped[1] = approved[0];
        _revertAs(SPONSOR, abi.encodeWithSelector(
            escrow.registerCommittedReviewerRoster.selector, bounty, swapped, uint8(2)
        ));
        bytes32[] memory changed = _sortedRoster(ORG1, keccak256("different-organization"));
        _revertAs(SPONSOR, abi.encodeWithSelector(
            escrow.registerCommittedReviewerRoster.selector, bounty, changed, uint8(2)
        ));
        _revertAs(SPONSOR, abi.encodeWithSelector(
            escrow.registerCommittedReviewerRoster.selector, bounty, approved, uint8(1)
        ));
        require(!escrow.getReviewerRoster(bounty).configured, "mismatched policy activated");
        vm.prank(SPONSOR);
        escrow.registerCommittedReviewerRoster(bounty, approved, 2);
        require(escrow.getReviewerRoster(bounty).configured, "correct policy blocked");
    }

    function testSignerCannotBeClaimedByMultipleOrgControllers() public {
        _enroll(ORG1, C1, S1);
        _activate(ORG1, C1);
        _enroll(ORG2, C2, S2);
        _activate(ORG2, C2);
        _revertAs(C2, abi.encodeWithSelector(escrow.proposeReviewerSigner.selector, ORG2, S1));
        require(escrow.walletOrganization(S1) == ORG1, "cross org identity rewrite");
    }
}
