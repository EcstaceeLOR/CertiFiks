// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Imports the TEST-ONLY funding harness, never a deployable custody contract.
import {PullHarnessV1} from "./PullWithdrawalModuleV1.t.sol";
import {BountyFundingModuleV1} from "../src/BountyFundingModuleV1.sol";

interface VmInvariantV1 {
    function chainId(uint256 value) external;
    function warp(uint256 value) external;
    function deal(address account, uint256 value) external;
    function prank(address account) external;
}

contract CreditAttackHandlerV1 {
    VmInvariantV1 private constant vm =
        VmInvariantV1(address(uint160(uint256(keccak256("hevm cheat code")))));

    PullHarnessV1 public immutable escrow;
    address public immutable sponsor;
    address public immutable outsider;
    uint256[3] private ids;
    uint256 public successfullyPaidAtoms;
    uint256 public successfulWithdrawals;
    uint256 public rejectedUnauthorizedWithdrawals;
    uint256 public rejectedReplayAccruals;

    constructor(PullHarnessV1 deployed, address sponsor_, address outsider_, uint256[3] memory bounties) {
        escrow = deployed;
        sponsor = sponsor_;
        outsider = outsider_;
        ids = bounties;
    }

    // The fuzzer chooses beneficiary, amount, destination and bounty. Every successful
    // payout is tracked independently from the contract's own liability totals.
    function withdraw(uint8 bountySelector, uint8 callerSelector, uint8 recipientSelector, uint96 requested) external {
        uint256 bounty = ids[uint256(bountySelector) % 3];
        address actor = callerSelector % 3 == 0 ? sponsor :
            callerSelector % 3 == 1 ? outsider : address(this);
        address payable destination = recipientSelector % 4 == 0 ? payable(address(0)) :
            recipientSelector % 4 == 1 ? payable(address(escrow)) :
            recipientSelector % 4 == 2 ? payable(outsider) : payable(sponsor);
        uint256 current = escrow.claimableByBounty(bounty, actor);
        uint256 amount = requested % 5 == 0 ? current :
            requested % 5 == 1 ? current + 1 :
            requested % 5 == 2 ? 0 : uint256(requested) % (3 ether) + 1;

        vm.prank(actor);
        (bool success,) = address(escrow).call(
            abi.encodeWithSelector(escrow.withdrawBountyCredit.selector, bounty, destination, amount)
        );
        if (success) {
            require(actor == sponsor, "foreign actor paid");
            require(destination != address(0) && destination != address(escrow), "invalid destination paid");
            require(amount > 0 && amount <= current, "invalid debit paid");
            successfullyPaidAtoms += amount;
            successfulWithdrawals++;
        } else if (actor != sponsor) {
            rejectedUnauthorizedWithdrawals++;
        }
    }

    function replayCredit(uint8 bountySelector) external {
        uint256 bounty = ids[uint256(bountySelector) % 3];
        (bool ok,) = address(escrow).call(
            abi.encodeWithSelector(escrow.accrueFinalCredits.selector, bounty)
        );
        // The first two were already accrued; the third has no entitlement.
        require(!ok, "replayed or unresolved credit was accepted");
        rejectedReplayAccruals++;
    }

    // The source escrow must reject a payout if execution is replayed on a
    // different chain, even for the legitimate beneficiary.
    function wrongChainWithdrawal(uint8 bountySelector, uint96 amountSeed) external {
        uint256 bounty = ids[uint256(bountySelector) % 3];
        uint256 claim = escrow.claimableByBounty(bounty, sponsor);
        uint256 amount = claim == 0 ? 1 : (uint256(amountSeed) % claim) + 1;
        vm.chainId(31338);
        vm.prank(sponsor);
        (bool ok,) = address(escrow).call(
            abi.encodeWithSelector(escrow.withdrawBountyCredit.selector, bounty, payable(sponsor), amount)
        );
        vm.chainId(31337);
        require(!ok, "cross-chain payout accepted");
    }

    // Attacker donations are not new escrow liabilities and cannot mint
    // claimable credits. This tests unexpected native balance changes.
    function forceNativeSurplus(uint96 surplusSeed) external {
        uint256 fundedBalance = escrow.totalReservedAtoms();
        uint256 extra = uint256(surplusSeed) % 1 ether;
        vm.deal(address(escrow), fundedBalance + extra);
        require(escrow.totalClaimableCreditsAtoms() <= fundedBalance, "surplus became credit");
    }

    function attemptCancel(uint8 bountySelector, bool impersonateSponsor) external {
        uint256 bounty = ids[uint256(bountySelector) % 3];
        // Cancellation must not re-open or duplicate already cancelled/refunded bounties.
        // The live third fixture may only be probed by an unauthorized actor:
        // we deliberately never grant this handler power to settle that fixture.
        address actor = bounty == ids[2] ? outsider :
            (impersonateSponsor ? sponsor : outsider);
        vm.prank(actor);
        (bool ok,) = address(escrow).call(
            abi.encodeWithSelector(escrow.cancelUnassignedBounty.selector, bounty)
        );
        require(!ok, "unauthorized or repeated cancellation accepted");
    }

    function attemptForeignAccrual(uint8 bountySelector, uint8 actorSelector) external {
        uint256 bounty = ids[uint256(bountySelector) % 3];
        vm.prank(actorSelector % 2 == 0 ? outsider : sponsor);
        (bool ok,) = address(escrow).call(
            abi.encodeWithSelector(escrow.accrueFinalCredits.selector, bounty)
        );
        require(!ok, "unexpected accrued entitlement");
    }
}

contract EscrowStatefulInvariantTest {
    VmInvariantV1 private constant vm =
        VmInvariantV1(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 private constant CHAIN = 31337;
    address private constant SPONSOR = address(0xA110);
    address private constant OUTSIDER = address(0xBAD);
    address private constant ARBITRATOR = address(0xA4B);
    address private constant FALLBACK = address(0xF411);
    uint256 private constant ORIGINAL_RESERVE = 6 ether;
    PullHarnessV1 private escrow;
    CreditAttackHandlerV1 private handler;
    uint256[3] private ids;

    function _policy() private view returns (BountyFundingModuleV1.FundingRequest memory request) {
        bytes32[] memory roster = new bytes32[](2);
        bytes32 a = keccak256("independent-reviewer-A");
        bytes32 b = keccak256("independent-reviewer-B");
        (roster[0], roster[1]) = a < b ? (a, b) : (b, a);
        request = BountyFundingModuleV1.FundingRequest({
            repositoryId: 888,
            baselineGitSha: hex"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            manifestDigest: bytes32(uint256(100)),
            verifierPolicyDigest: sha256(abi.encode("CertiFiks:verifier-roster:v1", uint8(2), roster)),
            disputePolicyDigest: sha256(abi.encode("CertiFiks:arbitration-policy:v1", ARBITRATOR, FALLBACK)),
            primaryArbitrator: ARBITRATOR,
            submissionDeadline: uint64(block.timestamp + 10 days),
            verificationSeconds: 2 days,
            challengeSeconds: 1 days,
            arbitrationSeconds: 2 days,
            assetKind: 0
        });
    }

    function setUp() public {
        vm.chainId(CHAIN);
        vm.warp(1780000000);
        vm.deal(SPONSOR, 10 ether);
        escrow = new PullHarnessV1(CHAIN, address(this));
        for (uint256 i = 0; i < 3; ++i) {
            // Compute SHA-256 precompile-backed policy commitments BEFORE prank:
            // sha256() makes an external precompile call and would consume vm.prank.
            BountyFundingModuleV1.FundingRequest memory request = _policy();
            vm.prank(SPONSOR);
            ids[i] = escrow.testFund{value: (i + 1) * 1 ether}(request);
            if (i < 2) {
                vm.prank(SPONSOR);
                escrow.cancelUnassignedBounty(ids[i]);
                escrow.recordNoSubmissionRefund(ids[i]);
                escrow.accrueFinalCredits(ids[i]);
            }
        }
        handler = new CreditAttackHandlerV1(escrow, SPONSOR, OUTSIDER, ids);
    }

    // Exposed in the exact shape read by the Foundry invariant engine; no forge-std dependency.
    function targetContracts() public view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    function invariant_escrowNativeAccountingAlwaysConserved() public view {
        uint256 remaining = escrow.totalReservedAtoms();
        uint256 credits = escrow.totalClaimableCreditsAtoms();
        require(remaining + handler.successfullyPaidAtoms() == ORIGINAL_RESERVE, "native conservation breached");
        require(credits <= remaining, "credited over reservation");
        require(escrow.claimableByBounty(ids[0], SPONSOR) +
            escrow.claimableByBounty(ids[1], SPONSOR) == credits, "ghost credit mismatch");
        require(escrow.claimableByBounty(ids[2], SPONSOR) == 0, "unresolved funds became withdrawable");
        require(escrow.claimableByBounty(ids[0], OUTSIDER) == 0, "outsider credited");
        require(escrow.claimableByBounty(ids[1], OUTSIDER) == 0, "outsider credited");
        require(address(escrow).balance >= remaining, "escrow insolvent");
        require(remaining - credits == 3 ether, "unresolved liability incorrectly released");
    }

    function invariant_noDuplicateCreditOrForeignPayout() public view {
        require(escrow.bountyCreditsAccrued(ids[0]), "first entitlement lost");
        require(escrow.bountyCreditsAccrued(ids[1]), "second entitlement lost");
        require(!escrow.bountyCreditsAccrued(ids[2]), "unresolved bounty accrued");
        require(handler.successfullyPaidAtoms() <= 3 ether, "withdrawals exceeded earned credits");
        require(escrow.claimableByBounty(ids[0], SPONSOR) <= 1 ether, "credit inflated");
        require(escrow.claimableByBounty(ids[1], SPONSOR) <= 2 ether, "credit inflated");
    }
}
