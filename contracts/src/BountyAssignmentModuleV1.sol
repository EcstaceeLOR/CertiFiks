// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BountyFundingModuleV1} from "./BountyFundingModuleV1.sol";

/**
 * @title BountyAssignmentModuleV1
 * @notice Applicant consent and conflict-free assignment for an immutable funded bounty.
 *
 * IMPORTANT: Abstract, NOT a safe standalone escrow. It inherits internal
 * funding and has no production payable funding function, refund transfer,
 * verification, arbitrator or withdrawal capability. Test-only funding and
 * submission harnesses live in contracts/test/. No real funds until #14-#18.
 *
 * Authorizations are EVM wallet-signed transactions (msg.sender), not an
 * unauthenticated HTTP callback or an operator-supplied address. Off-chain
 * GitHub/wallet identity binding, signer conflict policies and throttling
 * remain required by #12, #20, #23 and #24.
 */
abstract contract BountyAssignmentModuleV1 is BountyFundingModuleV1 {
    uint32 public constant MAX_PENDING_APPLICANTS = 32;
    uint64 public constant OFFER_TTL = 1 days;
    uint64 public constant MIN_WORK_WINDOW = 1 hours;

    enum ApplicationState {
        None,
        Applied,
        Offered,
        Accepted,
        Withdrawn,
        Rejected
    }

    enum AssignmentState {
        Open,
        Offered,
        Accepted,
        Submitted,
        CancelledPendingRefund,
        ExpiredPendingRefund
    }

    struct Assignment {
        AssignmentState state;
        address developer;
        address offeredTo;
        uint64 offerUntil;
        uint64 acceptedAt;
        uint32 pendingApplicants;
    }

    error IncorrectSender();
    error InvalidApplicant();
    error ApplicationAlreadyUsed();
    error ApplicationNotPending();
    error ApplicantLimitReached();
    error InvalidAssignmentState();
    error NotSelectedApplicant();
    error OfferExpired();
    error OfferNotExpired();
    error OfferTooLate();
    error SubmissionDeadlinePassed();

    event DeveloperApplied(uint256 indexed bountyId, address indexed applicant);
    event ApplicationWithdrawn(uint256 indexed bountyId, address indexed applicant);
    event ApplicationRejected(uint256 indexed bountyId, address indexed applicant);
    event AssignmentOffered(
        uint256 indexed bountyId,
        address indexed sponsor,
        address indexed applicant,
        uint64 offerUntil
    );
    event OfferRevoked(uint256 indexed bountyId, address indexed applicant);
    event OfferTimedOut(uint256 indexed bountyId, address indexed applicant);
    event AssignmentAccepted(uint256 indexed bountyId, address indexed developer);
    event AssignmentResigned(uint256 indexed bountyId, address indexed developer);
    event AssignmentSubmissionLocked(uint256 indexed bountyId, address indexed developer);
    event UnassignedBountyCancelled(uint256 indexed bountyId, address indexed sponsor);
    event UnsubmittedBountyExpired(uint256 indexed bountyId);

    mapping(uint256 => Assignment) internal _assignment;
    mapping(uint256 => mapping(address => ApplicationState)) internal _application;

    constructor(uint256 chainId) BountyFundingModuleV1(chainId) {}

    modifier onlyCorrectChain() {
        if (block.chainid != expectedChainId) {
            revert IncorrectChain(block.chainid, expectedChainId);
        }
        _;
    }

    function _terms(uint256 bountyId) internal view returns (BountyTerms storage terms) {
        if (bountyId == 0 || bountyId >= nextBountyId) revert UnknownBounty(bountyId);
        return _fundingTerms[bountyId];
    }

    function _onlySponsor(uint256 bountyId) internal view returns (BountyTerms storage terms) {
        terms = _terms(bountyId);
        if (msg.sender != terms.sponsor) revert IncorrectSender();
    }

    function _requireOpen(uint256 bountyId) internal view {
        if (_assignment[bountyId].state != AssignmentState.Open) revert InvalidAssignmentState();
    }

    function _requireWorkWindow(BountyTerms storage terms) internal view {
        // Even if the offer was just made, acceptance must leave reasonable
        // time for work. Conservative v1 constant cannot be changed post-funding.
        if (block.timestamp + MIN_WORK_WINDOW >= uint256(terms.submissionDeadline)) {
            revert OfferTooLate();
        }
    }

    function applyForBounty(uint256 bountyId) external onlyCorrectChain {
        BountyTerms storage terms = _terms(bountyId);
        // New applicants can join while another applicant considers an offer.
        // Only one offer / accepted contributor is allowed, not just one applicant.
        AssignmentState phase = _assignment[bountyId].state;
        if (phase != AssignmentState.Open && phase != AssignmentState.Offered) {
            revert InvalidAssignmentState();
        }
        _requireWorkWindow(terms);
        if (msg.sender == address(0) || msg.sender == terms.sponsor) revert InvalidApplicant();
        if (_application[bountyId][msg.sender] != ApplicationState.None) {
            revert ApplicationAlreadyUsed();
        }
        Assignment storage assignment = _assignment[bountyId];
        if (assignment.pendingApplicants >= MAX_PENDING_APPLICANTS) {
            revert ApplicantLimitReached();
        }
        // The sponsor can reject spam applications and open capacity. One
        // wallet can submit at most one application per bounty.
        _application[bountyId][msg.sender] = ApplicationState.Applied;
        assignment.pendingApplicants += 1;
        emit DeveloperApplied(bountyId, msg.sender);
    }

    function withdrawApplication(uint256 bountyId) external onlyCorrectChain {
        _terms(bountyId);
        ApplicationState application = _application[bountyId][msg.sender];
        if (application != ApplicationState.Applied && application != ApplicationState.Offered) {
            revert ApplicationNotPending();
        }
        Assignment storage assignment = _assignment[bountyId];
        if (application == ApplicationState.Offered) {
            if (assignment.state != AssignmentState.Offered || assignment.offeredTo != msg.sender) {
                revert InvalidAssignmentState();
            }
            _clearOffer(assignment);
        }
        assignment.pendingApplicants -= 1;
        _application[bountyId][msg.sender] = ApplicationState.Withdrawn;
        emit ApplicationWithdrawn(bountyId, msg.sender);
    }

    function rejectApplication(uint256 bountyId, address applicant) external onlyCorrectChain {
        _onlySponsor(bountyId);
        ApplicationState application = _application[bountyId][applicant];
        if (application != ApplicationState.Applied && application != ApplicationState.Offered) {
            revert ApplicationNotPending();
        }
        Assignment storage assignment = _assignment[bountyId];
        if (application == ApplicationState.Offered) {
            if (assignment.state != AssignmentState.Offered || assignment.offeredTo != applicant) {
                revert InvalidAssignmentState();
            }
            _clearOffer(assignment);
        }
        assignment.pendingApplicants -= 1;
        _application[bountyId][applicant] = ApplicationState.Rejected;
        emit ApplicationRejected(bountyId, applicant);
    }

    function offerAssignment(uint256 bountyId, address applicant) external onlyCorrectChain {
        BountyTerms storage terms = _onlySponsor(bountyId);
        _requireOpen(bountyId);
        _requireWorkWindow(terms);
        if (applicant == terms.sponsor || applicant == address(0)) revert InvalidApplicant();
        if (_application[bountyId][applicant] != ApplicationState.Applied) {
            revert ApplicationNotPending();
        }

        uint256 latestAcceptable = uint256(terms.submissionDeadline) - MIN_WORK_WINDOW;
        uint256 expiry = block.timestamp + OFFER_TTL;
        if (expiry > latestAcceptable) expiry = latestAcceptable;
        Assignment storage assignment = _assignment[bountyId];
        assignment.state = AssignmentState.Offered;
        assignment.offeredTo = applicant;
        assignment.offerUntil = uint64(expiry);
        _application[bountyId][applicant] = ApplicationState.Offered;

        emit AssignmentOffered(bountyId, msg.sender, applicant, uint64(expiry));
    }

    function revokeOffer(uint256 bountyId) external onlyCorrectChain {
        _onlySponsor(bountyId);
        Assignment storage assignment = _assignment[bountyId];
        if (assignment.state != AssignmentState.Offered) revert InvalidAssignmentState();
        address applicant = assignment.offeredTo;
        _application[bountyId][applicant] = ApplicationState.Applied;
        _clearOffer(assignment);
        emit OfferRevoked(bountyId, applicant);
    }

    function expireOffer(uint256 bountyId) external onlyCorrectChain {
        _terms(bountyId);
        Assignment storage assignment = _assignment[bountyId];
        if (assignment.state != AssignmentState.Offered) revert InvalidAssignmentState();
        if (block.timestamp <= assignment.offerUntil) revert OfferNotExpired();
        address applicant = assignment.offeredTo;
        _application[bountyId][applicant] = ApplicationState.Applied;
        _clearOffer(assignment);
        emit OfferTimedOut(bountyId, applicant);
    }

    function acceptAssignment(uint256 bountyId) external onlyCorrectChain {
        BountyTerms storage terms = _terms(bountyId);
        Assignment storage assignment = _assignment[bountyId];
        if (assignment.state != AssignmentState.Offered) revert InvalidAssignmentState();
        if (assignment.offeredTo != msg.sender) revert NotSelectedApplicant();
        if (_application[bountyId][msg.sender] != ApplicationState.Offered) {
            revert ApplicationNotPending();
        }
        if (block.timestamp > assignment.offerUntil) revert OfferExpired();
        _requireWorkWindow(terms);
        _validateAcceptedRole(bountyId, msg.sender);

        assignment.state = AssignmentState.Accepted;
        assignment.developer = msg.sender;
        assignment.offeredTo = address(0);
        assignment.offerUntil = 0;
        assignment.acceptedAt = uint64(block.timestamp);
        assignment.pendingApplicants -= 1;
        _application[bountyId][msg.sender] = ApplicationState.Accepted;
        emit AssignmentAccepted(bountyId, msg.sender);
    }

    /** Derived dispute module can reject conflicted arbiter wallets. */
    function _validateAcceptedRole(uint256, address) internal view virtual {}

    function resignAssignment(uint256 bountyId) external onlyCorrectChain {
        _terms(bountyId);
        Assignment storage assignment = _assignment[bountyId];
        if (assignment.state != AssignmentState.Accepted) revert InvalidAssignmentState();
        if (assignment.developer != msg.sender) revert IncorrectSender();
        // No unconsented sponsor replacement: only accepted developer may
        // resign BEFORE any submitted fix exists.
        assignment.state = AssignmentState.Open;
        assignment.developer = address(0);
        assignment.acceptedAt = 0;
        _application[bountyId][msg.sender] = ApplicationState.Withdrawn;
        emit AssignmentResigned(bountyId, msg.sender);
    }

    function cancelUnassignedBounty(uint256 bountyId) external onlyCorrectChain {
        _onlySponsor(bountyId);
        Assignment storage assignment = _assignment[bountyId];
        if (
            assignment.state != AssignmentState.Open &&
            assignment.state != AssignmentState.Offered
        ) revert InvalidAssignmentState();

        // This flags a FUTURE refund eligibility path. No ETH moves, no
        // payout claim is created. Actual refunds belong to #15/#16.
        if (assignment.state == AssignmentState.Offered) {
            address applicant = assignment.offeredTo;
            _application[bountyId][applicant] = ApplicationState.Applied;
            _clearOffer(assignment);
        }
        assignment.state = AssignmentState.CancelledPendingRefund;
        emit UnassignedBountyCancelled(bountyId, msg.sender);
    }

    function expireUnsubmittedBounty(uint256 bountyId) external onlyCorrectChain {
        BountyTerms storage terms = _terms(bountyId);
        if (block.timestamp <= terms.submissionDeadline) revert SubmissionDeadlinePassed();
        Assignment storage assignment = _assignment[bountyId];
        if (
            assignment.state != AssignmentState.Open &&
            assignment.state != AssignmentState.Offered &&
            assignment.state != AssignmentState.Accepted
        ) revert InvalidAssignmentState();
        if (assignment.state == AssignmentState.Offered) {
            _application[bountyId][assignment.offeredTo] = ApplicationState.Applied;
            _clearOffer(assignment);
        }
        // Accepted, but no timely submission. The future refund module must
        // check terminal chain state, rather than interpreting this event
        // itself as money transferred.
        assignment.state = AssignmentState.ExpiredPendingRefund;
        emit UnsubmittedBountyExpired(bountyId);
    }

    function _clearOffer(Assignment storage assignment) internal {
        assignment.state = AssignmentState.Open;
        assignment.offeredTo = address(0);
        assignment.offerUntil = 0;
    }

    function _assertCanSubmit(uint256 bountyId, address developer) internal view {
        BountyTerms storage terms = _terms(bountyId);
        Assignment storage assignment = _assignment[bountyId];
        if (
            developer == address(0) ||
            assignment.state != AssignmentState.Accepted ||
            assignment.developer != developer
        ) revert InvalidAssignmentState();
        if (block.timestamp > terms.submissionDeadline) revert SubmissionDeadlinePassed();
        if (block.chainid != expectedChainId) {
            revert IncorrectChain(block.chainid, expectedChainId);
        }
    }

    /**
     * @dev Called only by a future authenticated pinned-GitHub-submission
     * implementation (#11). No public implementation is exposed here.
     */
    function _lockTimelySubmission(uint256 bountyId) internal {
        // Never trust an arbitrary developer argument from a future API.
        // The same EVM wallet that accepted MUST sign the submission call.
        _assertCanSubmit(bountyId, msg.sender);
        _assignment[bountyId].state = AssignmentState.Submitted;
        emit AssignmentSubmissionLocked(bountyId, msg.sender);
    }

    function canSubmit(uint256 bountyId, address developer) external view returns (bool) {
        if (bountyId == 0 || bountyId >= nextBountyId) return false;
        Assignment storage assignment = _assignment[bountyId];
        return
            block.chainid == expectedChainId &&
            assignment.state == AssignmentState.Accepted &&
            developer != address(0) &&
            assignment.developer == developer &&
            block.timestamp <= _fundingTerms[bountyId].submissionDeadline;
    }

    function getAssignment(uint256 bountyId) external view returns (Assignment memory) {
        _terms(bountyId);
        return _assignment[bountyId];
    }

    function applicationState(uint256 bountyId, address applicant)
        external
        view
        returns (ApplicationState)
    {
        _terms(bountyId);
        return _application[bountyId][applicant];
    }
}
