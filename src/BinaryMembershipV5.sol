// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BinaryMembershipV4} from "./BinaryMembershipV4.sol";

/// @title BinaryMembershipV5
/// @notice Fixed-fee sequential USDT membership with immediate treasury and
/// company distribution on every paid entry.
/// @dev Each fee first pays valid uplines. The remainder is then split 50/50
/// in the same registration or stage-join transaction, leaving no entry-fee
/// treasury balance in the contract. `fundTreasury` remains available for
/// separately funded physical awards.
contract BinaryMembershipV5 is BinaryMembershipV4 {
    using SafeERC20 for IERC20;

    event TreasuryAutoSplit(uint256 totalAmount, uint256 treasuryAmount, uint256 companyAmount);

    constructor(
        IERC20 _asset,
        address _treasury,
        address _companyWallet,
        address _admin,
        uint48 _adminDelay,
        address _designatedRoot
    ) BinaryMembershipV4(_asset, _treasury, _companyWallet, _admin, _adminDelay, _designatedRoot) {}

    /// @dev Split the actual post-upline remainder immediately. An odd base
    /// unit is assigned to treasury so company never receives more than half.
    function _creditTreasury(uint256 amount) internal override {
        totalTreasuryPaid += amount;

        uint256 companyAmount = amount / 2;
        uint256 treasuryAmount = amount - companyAmount;

        if (treasuryAmount != 0) asset.safeTransfer(treasury, treasuryAmount);
        if (companyAmount != 0) asset.safeTransfer(companyWallet, companyAmount);

        emit TreasuryWithdrawn(treasury, treasuryAmount);
        emit CompanyProfitWithdrawn(companyWallet, companyAmount);
        emit TreasuryAutoSplit(amount, treasuryAmount, companyAmount);
    }
}
