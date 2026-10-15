// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FairEntitlementModuleV1} from "./FairEntitlementModuleV1.sol";

/**
 * @title PullWithdrawalModuleV1
 * @notice Per-bounty claimable native-asset credits and beneficiary-signed
 *         withdrawals. Never pushes money from settlement or arbitration.
 *
 * @dev ABSTRACT: There is NO externally callable production funding method.
 *      The funding-only test harness lives in contracts/test and must NEVER
 *      be deployed. The live GitHub/worker review and target-chain runtime
 *      remain unverified. Do not use with real user deposits before #17/#18
 *      and an external independent security review (#41).
 *
 *      totalReservedAtoms from #9 represents *all unpaid obligations*, both
 *      not-yet-finalized bounty rewards and credited balances. Minting an
 *      accounting credit DOES NOT reduce it. Only a successful withdrawal
 *      releases liabilities. Forced ETH transfers remain unreserved surplus.
 */
abstract contract PullWithdrawalModuleV1 is FairEntitlementModuleV1 {
    error CreditAlreadyAccrued();
    error NoFinalEntitlement();
    error InvalidCreditedBeneficiary();
    error CreditExceedsLiabilities();
    error UnsupportedPayoutAsset();
    error InvalidWithdrawalAmount();
    error InsufficientBeneficiaryCredit();
    error InvalidWithdrawalRecipient();
    error PayoutTransferFailed();
    error WithdrawalReentrancy();

    event NativeCreditAccrued(
        uint256 indexed bountyId,
        address indexed beneficiary,
        uint256 amountAtoms,
        Reason reason,
        bytes32 sourceAttemptDigest,
        bytes32 decisionReasonDigest
    );
    event NativeCreditWithdrawn(
        uint256 indexed bountyId,
        address indexed beneficiary,
        address indexed recipient,
        uint256 amountAtoms,
        uint256 remainingBeneficiaryAtoms
    );

    uint256 public totalClaimableCreditsAtoms;
    mapping(uint256 => bool) public bountyCreditsAccrued;
    mapping(uint256 => mapping(address => uint256)) public claimableByBounty;
    uint256 private _payoutEntered;

    constructor(uint256 chainId, address governance)
        FairEntitlementModuleV1(chainId, governance)
    {}

    modifier noPayoutReentrancy() {
        if (_payoutEntered != 0) revert WithdrawalReentrancy();
        _payoutEntered = 1;
        _;
        _payoutEntered = 0;
    }

    /**
     * @notice Anyone may finish *accounting only* after a valid #15
     *         entitlement has been immutably recorded. Exactly once.
     *         Does not transfer ETH or make arbitrator rulings.
     */
    function accrueFinalCredits(uint256 bountyId)
        external onlyCorrectChain noPayoutReentrancy
    {
        BountyTerms storage terms = _terms(bountyId);
        if (bountyCreditsAccrued[bountyId]) revert CreditAlreadyAccrued();
        if (terms.assetKind != uint8(AssetKind.Native)) revert UnsupportedPayoutAsset();

        Entitlement storage decision = _entitlements[bountyId];
        if (decision.reason == Reason.None) revert NoFinalEntitlement();
        if (
            decision.sponsor != terms.sponsor ||
            decision.sponsor == address(0) ||
            decision.sponsorAtoms + decision.developerAtoms != terms.rewardAtoms ||
            (decision.developerAtoms != 0 && (
                decision.developer == address(0) ||
                decision.developer == decision.sponsor
            ))
        ) revert InvalidCreditedBeneficiary();

        // Effects precede any external calls. The immutable payout amounts
        // are credited on *exactly one* bounty, including 50/50 resolutions.
        bountyCreditsAccrued[bountyId] = true;
        if (decision.sponsorAtoms != 0) {
            claimableByBounty[bountyId][decision.sponsor] += decision.sponsorAtoms;
            emit NativeCreditAccrued(
                bountyId, decision.sponsor, decision.sponsorAtoms,
                decision.reason, decision.sourceAttemptDigest, decision.decisionReasonDigest
            );
        }
        if (decision.developerAtoms != 0) {
            claimableByBounty[bountyId][decision.developer] += decision.developerAtoms;
            emit NativeCreditAccrued(
                bountyId, decision.developer, decision.developerAtoms,
                decision.reason, decision.sourceAttemptDigest, decision.decisionReasonDigest
            );
        }
        totalClaimableCreditsAtoms += terms.rewardAtoms;
        if (
            totalClaimableCreditsAtoms > totalReservedAtoms ||
            address(this).balance < totalReservedAtoms
        ) revert CreditExceedsLiabilities();
    }

    /**
     * @notice An *actual beneficiary wallet* may withdraw any portion of its
     *         own accrued credit to an explicitly authorized recipient.
     *
     * No sponsor, verifier, governance actor, or relayer can select somebody
     * else's recipient. No allowance, admin sweep, selfdestruct rescue or
     * EIP-2771 forwarded sender is trusted here. Each call emits an on-chain
     * receipt containing the exact bounty, beneficiary, recipient and atoms.
     *
     * Checks -> accounting effects -> transfer. On failure the whole call
     * reverts and the prior credit remains intact, available for retry.
     */
    function withdrawBountyCredit(uint256 bountyId, address payable recipient, uint256 amountAtoms)
        external onlyCorrectChain noPayoutReentrancy
    {
        _terms(bountyId);
        if (recipient == address(0) || recipient == address(this)) {
            revert InvalidWithdrawalRecipient();
        }
        if (amountAtoms == 0) revert InvalidWithdrawalAmount();
        uint256 owed = claimableByBounty[bountyId][msg.sender];
        if (amountAtoms > owed) revert InsufficientBeneficiaryCredit();

        claimableByBounty[bountyId][msg.sender] = owed - amountAtoms;
        totalClaimableCreditsAtoms -= amountAtoms;
        totalReservedAtoms -= amountAtoms;

        (bool paid,) = recipient.call{value: amountAtoms}("");
        if (!paid) revert PayoutTransferFailed();

        // External recipient cannot create a liability deficit, even if
        // recipient accepts a low-gas callback or another user funds meanwhile.
        if (
            totalClaimableCreditsAtoms > totalReservedAtoms ||
            address(this).balance < totalReservedAtoms
        ) revert CreditExceedsLiabilities();

        emit NativeCreditWithdrawn(
            bountyId, msg.sender, recipient, amountAtoms,
            claimableByBounty[bountyId][msg.sender]
        );
    }

    function unfinalizedRewardLiabilitiesAtoms() external view returns (uint256) {
        // The distinction is important when displaying funded-but-unresolved
        // bounties versus credits already available for withdrawal.
        return totalReservedAtoms - totalClaimableCreditsAtoms;
    }

    function nativeLiabilityHealth()
        external view returns (uint256 reservedAtoms, uint256 creditsAtoms, uint256 surplusAtoms, bool solvent)
    {
        reservedAtoms = totalReservedAtoms;
        creditsAtoms = totalClaimableCreditsAtoms;
        solvent = creditsAtoms <= reservedAtoms && address(this).balance >= reservedAtoms;
        surplusAtoms = address(this).balance > reservedAtoms
            ? address(this).balance - reservedAtoms
            : 0;
    }
}
