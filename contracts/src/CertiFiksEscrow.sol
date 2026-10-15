// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title CertiFiksEscrow (HISTORICAL PROOFPATCH STARTER — UNREVIEWED)
 * @notice Baseline experimental native-asset escrow from the earlier ProofPatch starter.
 * @dev DO NOT DEPLOY WITH REAL FUNDS. This intentionally retains known defects for
 *      review and regression tests in #6, #14–#17:
 *      - sponsor can refund after a timely submitted fix if verifiers time out;
 *      - direct ETH/native transfers can revert and permanently obstruct payout;
 *      - two distinct wallets do not prove independent verifier controllers;
 *      - arbitrator can disappear and leave funds indefinitely disputed.
 *      No real Portaldot V3 EVM deployment is verified.
 */
contract CertiFiksEscrow {
    enum Status { None, Open, Submitted, Approved, Disputed, Paid, Refunded }

    struct Bounty {
        address payable sponsor;
        address payable developer;
        address verifierA;
        address verifierB;
        address arbitrator;
        bytes32 specificationHash;
        bytes32 submissionHash;
        bytes32 reportA;
        bytes32 reportB;
        uint256 reward;
        uint64 deadline;
        uint64 submittedAt;
        uint64 approvedAt;
        uint64 challengeSeconds;
        uint64 verificationSeconds;
        uint8 votes;
        bool passA;
        bool passB;
        Status status;
    }

    uint256 public nextBountyId = 1;
    mapping(uint256 => Bounty) private _bounties;
    bool private _entered;

    event BountyCreated(uint256 indexed id, address indexed sponsor, uint256 reward, bytes32 specificationHash);
    event DeveloperAssigned(uint256 indexed id, address indexed developer);
    event FixSubmitted(uint256 indexed id, address indexed developer, bytes32 submissionHash);
    event VerificationRecorded(uint256 indexed id, address indexed verifier, bool passed, bytes32 reportHash);
    event BountyApproved(uint256 indexed id, uint64 approvedAt);
    event BountyDisputed(uint256 indexed id, bytes32 reasonHash);
    event BountyPaid(uint256 indexed id, address indexed developer, uint256 amount);
    event BountyRefunded(uint256 indexed id, address indexed sponsor, uint256 amount);

    modifier nonReentrant() {
        require(!_entered, "reentrancy");
        _entered = true;
        _;
        _entered = false;
    }

    function bounty(uint256 id) external view returns (Bounty memory) {
        return _bounties[id];
    }

    function createBounty(
        bytes32 specificationHash,
        address verifierA,
        address verifierB,
        address arbitrator,
        uint64 deadline,
        uint64 challengeSeconds,
        uint64 verificationSeconds
    ) external payable returns (uint256 id) {
        require(msg.value > 0, "unfunded");
        require(specificationHash != bytes32(0), "missing specification");
        require(deadline > block.timestamp, "deadline passed");
        require(challengeSeconds >= 1 hours && challengeSeconds <= 30 days, "challenge window");
        require(verificationSeconds >= 1 hours && verificationSeconds <= 30 days, "verification window");
        require(verifierA != address(0) && verifierB != address(0) && arbitrator != address(0), "zero role");
        require(verifierA != verifierB && verifierA != msg.sender && verifierB != msg.sender, "verifier conflict");
        require(arbitrator != verifierA && arbitrator != verifierB && arbitrator != msg.sender, "arbitrator conflict");

        id = nextBountyId++;
        Bounty storage b = _bounties[id];
        b.sponsor = payable(msg.sender);
        b.verifierA = verifierA;
        b.verifierB = verifierB;
        b.arbitrator = arbitrator;
        b.specificationHash = specificationHash;
        b.reward = msg.value;
        b.deadline = deadline;
        b.challengeSeconds = challengeSeconds;
        b.verificationSeconds = verificationSeconds;
        b.status = Status.Open;
        emit BountyCreated(id, msg.sender, msg.value, specificationHash);
    }

    function assignDeveloper(uint256 id, address payable selectedDeveloper) external {
        Bounty storage b = _bounties[id];
        require(msg.sender == b.sponsor && b.status == Status.Open && block.timestamp <= b.deadline, "not assignable");
        require(b.developer == address(0), "already assigned");
        require(
            selectedDeveloper != address(0) && selectedDeveloper != b.sponsor &&
            selectedDeveloper != b.verifierA && selectedDeveloper != b.verifierB &&
            selectedDeveloper != b.arbitrator,
            "developer role conflict"
        );
        b.developer = selectedDeveloper;
        emit DeveloperAssigned(id, selectedDeveloper);
    }

    function submitFix(uint256 id, bytes32 submissionHash) external {
        Bounty storage b = _bounties[id];
        require(b.status == Status.Open && block.timestamp <= b.deadline, "not open");
        require(submissionHash != bytes32(0), "empty submission");
        require(msg.sender == b.developer && msg.sender != address(0), "not assigned developer");
        b.submissionHash = submissionHash;
        b.submittedAt = uint64(block.timestamp);
        b.status = Status.Submitted;
        emit FixSubmitted(id, msg.sender, submissionHash);
    }

    function recordVerification(uint256 id, bool passed, bytes32 reportHash) external {
        Bounty storage b = _bounties[id];
        require(b.status == Status.Submitted, "not submitted");
        require(block.timestamp <= uint256(b.submittedAt) + b.verificationSeconds, "verification expired");
        require(reportHash != bytes32(0), "empty report");

        if (msg.sender == b.verifierA) {
            require((b.votes & 1) == 0, "duplicate verifier");
            b.votes |= 1;
            b.passA = passed;
            b.reportA = reportHash;
        } else if (msg.sender == b.verifierB) {
            require((b.votes & 2) == 0, "duplicate verifier");
            b.votes |= 2;
            b.passB = passed;
            b.reportB = reportHash;
        } else revert("unauthorized verifier");

        emit VerificationRecorded(id, msg.sender, passed, reportHash);

        if (b.votes == 3) {
            if (b.passA && b.passB) {
                b.status = Status.Approved;
                b.approvedAt = uint64(block.timestamp);
                emit BountyApproved(id, b.approvedAt);
            } else {
                b.status = Status.Disputed;
                emit BountyDisputed(id, keccak256("verification disagreement"));
            }
        }
    }

    function challenge(uint256 id, bytes32 reasonHash) external {
        Bounty storage b = _bounties[id];
        require(msg.sender == b.sponsor && b.status == Status.Approved, "not challengeable");
        require(block.timestamp < uint256(b.approvedAt) + b.challengeSeconds, "challenge ended");
        require(reasonHash != bytes32(0), "empty reason");
        b.status = Status.Disputed;
        emit BountyDisputed(id, reasonHash);
    }

    function settle(uint256 id) external nonReentrant {
        Bounty storage b = _bounties[id];
        require(b.status == Status.Approved, "not approved");
        require(block.timestamp >= uint256(b.approvedAt) + b.challengeSeconds, "challenge pending");
        _payDeveloper(id, b);
    }

    /** @dev Human arbitrator is trusted and can be permanently unavailable (UNSAFE). */
    function resolveDispute(uint256 id, bool payDeveloper) external nonReentrant {
        Bounty storage b = _bounties[id];
        require(b.status == Status.Disputed && msg.sender == b.arbitrator, "not arbitrator");
        if (payDeveloper) _payDeveloper(id, b);
        else _refundSponsor(id, b);
    }

    /** @dev WARNING: sponsor refund after timed-out timely submission is a known defect. */
    function refundExpired(uint256 id) external nonReentrant {
        Bounty storage b = _bounties[id];
        require(msg.sender == b.sponsor, "not sponsor");
        bool neverSubmitted = b.status == Status.Open && block.timestamp > b.deadline;
        bool verificationTimedOut =
            b.status == Status.Submitted && block.timestamp > uint256(b.submittedAt) + b.verificationSeconds;
        require(neverSubmitted || verificationTimedOut, "not refundable");
        _refundSponsor(id, b);
    }

    function _payDeveloper(uint256 id, Bounty storage b) internal {
        uint256 amount = b.reward;
        b.reward = 0;
        b.status = Status.Paid;
        (bool ok,) = b.developer.call{value: amount}("");
        require(ok, "developer payment failed");
        emit BountyPaid(id, b.developer, amount);
    }

    function _refundSponsor(uint256 id, Bounty storage b) internal {
        uint256 amount = b.reward;
        b.reward = 0;
        b.status = Status.Refunded;
        (bool ok,) = b.sponsor.call{value: amount}("");
        require(ok, "sponsor refund failed");
        emit BountyRefunded(id, b.sponsor, amount);
    }
}
