// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {CertiFiksEscrow} from "../src/CertiFiksEscrow.sol";

/// @notice Compiles and exercises only the historical constructor; this is NOT an escrow safety test.
contract CertiFiksBaselineTest {
    function testInitialBountyId() public {
        CertiFiksEscrow escrow = new CertiFiksEscrow();
        require(escrow.nextBountyId() == 1, "wrong initial id");
    }
}
