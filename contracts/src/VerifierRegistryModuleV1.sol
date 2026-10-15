// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BountySubmissionModuleV1} from "./BountySubmissionModuleV1.sol";

/**
 * @notice Permissioned, accountable reviewer organizations for CertiFiks.
 * @dev ABSTRACT and NOT a deployable escrow. Governance admission and
 * signatures are social/organizational trust assumptions, not proofs of
 * beneficial ownership, Sybil resistance, valid tests or fix correctness.
 *
 * Each admitted organization has exactly one CURRENT signer and one pinned
 * controller. Historic signer addresses stay linked to the same org forever;
 * registering a second key cannot add an independent organization.
 * Real reviewer attestation signatures, decisions and payouts are #13-#17.
 */
abstract contract VerifierRegistryModuleV1 is BountySubmissionModuleV1 {
    uint8 public constant MAX_REVIEWER_ORGS_PER_ATTEMPT = 5;
    bytes internal constant ROSTER_DOMAIN = "CertiFiks:verifier-roster:v1";

    struct ReviewerRoster {
        bytes32 policyDigest;
        uint8 quorum;
        uint8 eligibleOrganizations;
        bool configured;
    }

    struct ReviewerOrganization {
        address controller;
        address currentSigner;
        address proposedSigner;
        bytes32 identityEvidenceDigest;
        bytes32 capabilityProfileDigest;
        bytes32 conflictDisclosureDigest;
        uint64 signerEpoch;
        uint64 acceptedJobCount;
        uint64 declaredEvidenceCount;
        bool active;
        bool revokedPermanently;
        bool everRegistered;
    }

    struct ReviewerJob {
        bytes32 organizationId;
        uint64 attemptId;
        uint64 signerEpoch;
        uint64 assignedAt;
        uint64 deadline;
        address assignedSigner;
        bytes32 attemptDigest;
        bytes32 capabilityProfileDigest;
        bytes32 declaredReportDigest;
        bool accepted;
        bool exists;
    }

    error NotRegistryGovernance();
    error InvalidOrganization();
    error AlreadyEnrolled();
    error WalletBelongsToAnotherOrganization();
    error NotOrganizationController();
    error OrganizationInactive();
    error OrganizationAlreadyActive();
    error OrganizationPermanentlyRevoked();
    error ConflictingBountyRole();
    error InvalidReviewState();
    error DuplicateReviewerJob();
    error ReviewerLimitReached();
    error ReviewerJobMissing();
    error ReviewerJobExpired();
    error ReviewerNotAssigned();
    error ReviewAlreadyAccepted();
    error ReviewAlreadyDeclared();
    error InvalidReviewEvidence();
    error NoPendingSignerRotation();
    error StaleSignerEpoch();
    error InvalidSigner();
    error InvalidReviewerRoster();
    error ReviewerRosterAlreadyConfigured();
    error ReviewerRosterPolicyMismatch();
    error ReviewerNotInCommittedRoster();

    event ReviewerOrganizationEnrolled(
        bytes32 indexed organizationId, address indexed controller, address indexed signer,
        bytes32 identityEvidenceDigest, bytes32 capabilityProfileDigest,
        bytes32 conflictDisclosureDigest
    );
    event ReviewerOrganizationActivated(bytes32 indexed organizationId, uint64 signerEpoch);
    event ReviewerOrganizationRevoked(bytes32 indexed organizationId, uint64 signerEpoch);
    event ReviewerSignerRotationProposed(bytes32 indexed organizationId, address indexed proposedSigner);
    event ReviewerSignerRotated(bytes32 indexed organizationId, address indexed newSigner, uint64 epoch);
    event ReviewerCapabilityUpdated(bytes32 indexed organizationId, bytes32 profileDigest);
    event ReviewerRosterConfigured(
        uint256 indexed bountyId, bytes32 policyDigest, uint8 quorum, uint8 eligibleOrganizations
    );
    event ReviewerJobAssigned(
        uint256 indexed bountyId, uint64 indexed attemptId, bytes32 indexed organizationId,
        address assignedSigner, uint64 epoch, uint64 deadline, bytes32 attemptDigest
    );
    event ReviewerJobRefreshed(
        uint256 indexed bountyId, uint64 indexed attemptId, bytes32 indexed organizationId,
        address assignedSigner, uint64 epoch
    );
    event ReviewerJobAccepted(
        uint256 indexed bountyId, uint64 indexed attemptId, bytes32 indexed organizationId,
        address signer
    );
    event ReviewerEvidenceDeclared(
        uint256 indexed bountyId, uint64 indexed attemptId, bytes32 indexed organizationId,
        address signer, bytes32 reportDigest
    );

    address public immutable registryGovernance;

    mapping(bytes32 => ReviewerOrganization) internal _org;
    mapping(uint256 => ReviewerRoster) public reviewerRoster;
    mapping(uint256 => mapping(bytes32 => bool)) public isCommittedReviewer;
    mapping(address => bytes32) public walletOrganization;
    mapping(uint256 => mapping(uint64 => mapping(bytes32 => ReviewerJob))) internal _jobs;
    mapping(uint256 => mapping(uint64 => uint8)) public reviewerJobCount;

    constructor(uint256 chainId, address governance) BountySubmissionModuleV1(chainId) {
        if (governance == address(0)) revert NotRegistryGovernance();
        registryGovernance = governance;
    }

    modifier onlyRegistryGovernance() {
        if (msg.sender != registryGovernance) revert NotRegistryGovernance();
        _;
    }

    function _bindWallet(bytes32 organizationId, address wallet) private {
        if (wallet == address(0)) revert InvalidSigner();
        bytes32 oldOrgId = walletOrganization[wallet];
        if (oldOrgId != bytes32(0) && oldOrgId != organizationId) {
            revert WalletBelongsToAnotherOrganization();
        }
        walletOrganization[wallet] = organizationId;
    }

    /**
     * @dev Admission is permissioned: governance must independently inspect
     * named operator, shared control, domain and beneficial-ownership evidence.
     * Hashes do not independently prove any claim. Activation requires a
     * separate transaction from the enrolled controller.
     */
    function enrollReviewerOrganization(
        bytes32 organizationId, address controller, address signer,
        bytes32 identityDigest, bytes32 capabilityDigest, bytes32 conflictDigest
    ) external onlyCorrectChain onlyRegistryGovernance {
        if (
            organizationId == bytes32(0) || identityDigest == bytes32(0) ||
            capabilityDigest == bytes32(0) || conflictDigest == bytes32(0)
        ) revert InvalidOrganization();
        if (_org[organizationId].everRegistered) revert AlreadyEnrolled();
        _bindWallet(organizationId, controller);
        _bindWallet(organizationId, signer);
        ReviewerOrganization storage organization = _org[organizationId];
        organization.controller = controller;
        organization.currentSigner = signer;
        organization.identityEvidenceDigest = identityDigest;
        organization.capabilityProfileDigest = capabilityDigest;
        organization.conflictDisclosureDigest = conflictDigest;
        organization.signerEpoch = 1;
        organization.everRegistered = true;
        emit ReviewerOrganizationEnrolled(
            organizationId, controller, signer, identityDigest, capabilityDigest, conflictDigest
        );
    }

    function activateReviewerOrganization(bytes32 organizationId) external onlyCorrectChain {
        ReviewerOrganization storage organization = _registered(organizationId);
        if (organization.controller != msg.sender) revert NotOrganizationController();
        if (organization.active) revert OrganizationAlreadyActive();
        if (organization.revokedPermanently) revert OrganizationPermanentlyRevoked();
        organization.active = true;
        emit ReviewerOrganizationActivated(organizationId, organization.signerEpoch);
    }

    function revokeReviewerOrganization(bytes32 organizationId)
        external onlyCorrectChain onlyRegistryGovernance
    {
        ReviewerOrganization storage organization = _active(organizationId);
        organization.active = false;
        organization.revokedPermanently = true;
        organization.proposedSigner = address(0);
        emit ReviewerOrganizationRevoked(organizationId, organization.signerEpoch);
        // Do NOT delete historic job snapshots or past declarations.
    }

    function proposeReviewerSigner(bytes32 organizationId, address newSigner) external onlyCorrectChain {
        ReviewerOrganization storage organization = _active(organizationId);
        if (organization.controller != msg.sender) revert NotOrganizationController();
        if (newSigner == address(0) || newSigner == organization.currentSigner) {
            revert InvalidSigner();
        }
        // Reserve no external authorization: governance checks the proposed
        // key and controller statement before approving; the key must later
        // sign each assigned job itself.
        if (walletOrganization[newSigner] != bytes32(0) &&
            walletOrganization[newSigner] != organizationId) {
            revert WalletBelongsToAnotherOrganization();
        }
        organization.proposedSigner = newSigner;
        emit ReviewerSignerRotationProposed(organizationId, newSigner);
    }

    function approveReviewerSignerRotation(bytes32 organizationId)
        external onlyCorrectChain onlyRegistryGovernance
    {
        ReviewerOrganization storage organization = _active(organizationId);
        address nextSigner = organization.proposedSigner;
        if (nextSigner == address(0)) revert NoPendingSignerRotation();
        _bindWallet(organizationId, nextSigner);
        organization.currentSigner = nextSigner;
        organization.proposedSigner = address(0);
        organization.signerEpoch += 1;
        emit ReviewerSignerRotated(organizationId, nextSigner, organization.signerEpoch);
    }

    function updateReviewerCapability(bytes32 organizationId, bytes32 digest)
        external onlyCorrectChain onlyRegistryGovernance
    {
        ReviewerOrganization storage organization = _active(organizationId);
        if (digest == bytes32(0)) revert InvalidOrganization();
        organization.capabilityProfileDigest = digest;
        emit ReviewerCapabilityUpdated(organizationId, digest);
        // Per-job capability and epoch snapshots do NOT mutate.
    }

    function _registered(bytes32 organizationId)
        internal view returns (ReviewerOrganization storage organization)
    {
        organization = _org[organizationId];
        if (!organization.everRegistered) revert InvalidOrganization();
    }

    function _active(bytes32 organizationId)
        internal view returns (ReviewerOrganization storage organization)
    {
        organization = _registered(organizationId);
        if (!organization.active) revert OrganizationInactive();
    }

    function _requireNoRoleConflict(uint256 bountyId, bytes32 organizationId)
        internal view
    {
        BountyTerms storage terms = _terms(bountyId);
        ReviewerOrganization storage organization = _org[organizationId];
        address developer = _assignment[bountyId].developer;
        // Old signing wallets of this org remain linked forever, so an
        // enrolled organization cannot bypass role conflict by rotating key.
        if (
            terms.sponsor == organization.controller ||
            terms.sponsor == organization.currentSigner ||
            developer == organization.controller ||
            developer == organization.currentSigner ||
            terms.primaryArbitrator == organization.controller ||
            terms.primaryArbitrator == organization.currentSigner ||
            walletOrganization[terms.sponsor] == organizationId ||
            walletOrganization[developer] == organizationId ||
            walletOrganization[terms.primaryArbitrator] == organizationId
        ) revert ConflictingBountyRole();
    }

    /**
     * @notice One-time sponsor declaration of the EXACT originally funded,
     * ordered organization set. Different, reordered or added organizations
     * produce a different SHA-256 digest and cannot be substituted by admin.
     * Registration must precede developer acceptance/submission.
     */
    function registerCommittedReviewerRoster(
        uint256 bountyId, bytes32[] calldata organizationIds, uint8 quorum
    ) external onlyCorrectChain {
        BountyTerms storage terms = _onlySponsor(bountyId);
        if (reviewerRoster[bountyId].configured) revert ReviewerRosterAlreadyConfigured();
        if (_assignment[bountyId].state != AssignmentState.Open) revert InvalidReviewState();
        if (
            organizationIds.length < 2 || organizationIds.length > MAX_REVIEWER_ORGS_PER_ATTEMPT ||
            quorum < 2 || quorum > organizationIds.length
        ) revert InvalidReviewerRoster();
        bytes32 previous = bytes32(0);
        for (uint256 i = 0; i < organizationIds.length; i++) {
            bytes32 orgId = organizationIds[i];
            // Strict increasing ordering prevents duplicates / order ambiguity.
            if (orgId <= previous) revert InvalidReviewerRoster();
            previous = orgId;
        }
        bytes32 commitment = sha256(abi.encode(ROSTER_DOMAIN, quorum, organizationIds));
        if (commitment != terms.verifierPolicyDigest) revert ReviewerRosterPolicyMismatch();

        reviewerRoster[bountyId] = ReviewerRoster({
            policyDigest: commitment,
            quorum: quorum,
            eligibleOrganizations: uint8(organizationIds.length),
            configured: true
        });
        for (uint256 i = 0; i < organizationIds.length; i++) {
            isCommittedReviewer[bountyId][organizationIds[i]] = true;
        }
        emit ReviewerRosterConfigured(
            bountyId, commitment, quorum, uint8(organizationIds.length)
        );
    }

    /**
     * @dev Governance appoints an identity-checked org to an exact submitted
     * attempt. No arbitrary sponsor can appoint itself or create a reviewer
     * identity. This is not yet verifier attestation or payout permission.
     */
    function assignReviewerJob(uint256 bountyId, bytes32 organizationId)
        external onlyCorrectChain onlyRegistryGovernance
    {
        if (!reviewerRoster[bountyId].configured || !isCommittedReviewer[bountyId][organizationId]) {
            revert ReviewerNotInCommittedRoster();
        }
        ReviewerOrganization storage organization = _active(organizationId);
        if (_assignment[bountyId].state != AssignmentState.Submitted) revert InvalidReviewState();
        uint64 attemptId = latestAttemptId[bountyId];
        if (attemptId == 0) revert NoSubmission();
        if (reviewerJobCount[bountyId][attemptId] >= MAX_REVIEWER_ORGS_PER_ATTEMPT) {
            revert ReviewerLimitReached();
        }
        ReviewerJob storage job = _jobs[bountyId][attemptId][organizationId];
        if (job.exists) revert DuplicateReviewerJob();
        _requireNoRoleConflict(bountyId, organizationId);
        uint256 deadline = uint256(_attempts[bountyId][attemptId].submittedAt) +
            uint256(_terms(bountyId).verificationSeconds);
        if (block.timestamp >= deadline || deadline > type(uint64).max) revert ReviewerJobExpired();

        job.organizationId = organizationId;
        job.attemptId = attemptId;
        job.signerEpoch = organization.signerEpoch;
        job.assignedSigner = organization.currentSigner;
        job.assignedAt = uint64(block.timestamp);
        job.deadline = uint64(deadline);
        job.capabilityProfileDigest = organization.capabilityProfileDigest;
        job.attemptDigest = _attempts[bountyId][attemptId].attemptDigest;
        job.exists = true;
        reviewerJobCount[bountyId][attemptId] += 1;
        emit ReviewerJobAssigned(
            bountyId, attemptId, organizationId, job.assignedSigner,
            job.signerEpoch, job.deadline, job.attemptDigest
        );
    }

    /**
     * @notice Governance may update an unaccepted, undeclared job to current
     * key epoch. Historical declared evidence is NEVER reset or overwritten.
     */
    function refreshUnacceptedJob(uint256 bountyId, uint64 attemptId, bytes32 organizationId)
        external onlyCorrectChain onlyRegistryGovernance
    {
        ReviewerOrganization storage organization = _active(organizationId);
        ReviewerJob storage job = _job(bountyId, attemptId, organizationId);
        if (job.accepted || job.declaredReportDigest != bytes32(0)) revert ReviewAlreadyAccepted();
        if (block.timestamp >= job.deadline) revert ReviewerJobExpired();
        _requireNoRoleConflict(bountyId, organizationId);
        job.signerEpoch = organization.signerEpoch;
        job.assignedSigner = organization.currentSigner;
        job.capabilityProfileDigest = organization.capabilityProfileDigest;
        emit ReviewerJobRefreshed(
            bountyId, attemptId, organizationId, job.assignedSigner, job.signerEpoch
        );
    }

    function _job(uint256 bountyId, uint64 attemptId, bytes32 organizationId)
        internal view returns (ReviewerJob storage job)
    {
        job = _jobs[bountyId][attemptId][organizationId];
        if (!job.exists) revert ReviewerJobMissing();
    }

    function _authorizedJob(uint256 bountyId, uint64 attemptId, bytes32 organizationId)
        internal view returns (ReviewerJob storage job)
    {
        ReviewerOrganization storage organization = _active(organizationId);
        job = _job(bountyId, attemptId, organizationId);
        if (
            latestAttemptId[bountyId] != attemptId ||
            _assignment[bountyId].state != AssignmentState.Submitted
        ) revert InvalidReviewState();
        if (block.timestamp >= job.deadline) revert ReviewerJobExpired();
        if (organization.signerEpoch != job.signerEpoch) revert StaleSignerEpoch();
        if (msg.sender != job.assignedSigner ||
            msg.sender != organization.currentSigner) revert ReviewerNotAssigned();
        _requireNoRoleConflict(bountyId, organizationId);
    }

    function acceptReviewerJob(uint256 bountyId, uint64 attemptId, bytes32 organizationId)
        external onlyCorrectChain
    {
        ReviewerJob storage job = _authorizedJob(bountyId, attemptId, organizationId);
        if (job.accepted) revert ReviewAlreadyAccepted();
        job.accepted = true;
        _org[organizationId].acceptedJobCount += 1;
        emit ReviewerJobAccepted(bountyId, attemptId, organizationId, msg.sender);
    }

    /**
     * @notice The assigned reviewer submits an immutable report hash in a
     * wallet-authenticated transaction. This is NOT the independently signed
     * verification verdict or quorum logic (issue #13).
     */
    function declareReviewerEvidence(
        uint256 bountyId, uint64 attemptId, bytes32 organizationId, bytes32 reportDigest
    ) external onlyCorrectChain {
        ReviewerJob storage job = _authorizedJob(bountyId, attemptId, organizationId);
        if (!job.accepted) revert ReviewAlreadyAccepted();
        if (job.declaredReportDigest != bytes32(0)) revert ReviewAlreadyDeclared();
        if (reportDigest == bytes32(0)) revert InvalidReviewEvidence();
        job.declaredReportDigest = reportDigest;
        _org[organizationId].declaredEvidenceCount += 1;
        emit ReviewerEvidenceDeclared(bountyId, attemptId, organizationId, msg.sender, reportDigest);
    }

    function getReviewerOrganization(bytes32 organizationId)
        external view returns (ReviewerOrganization memory)
    {
        return _registered(organizationId);
    }

    function getReviewerJob(uint256 bountyId, uint64 attemptId, bytes32 organizationId)
        external view returns (ReviewerJob memory)
    {
        _terms(bountyId);
        return _job(bountyId, attemptId, organizationId);
    }
}
