// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BinaryMembershipV1} from "./BinaryMembershipV1.sol";

/// @title BinaryMembershipV4
/// @notice Fixed-fee, sequential-stage membership paid in USDT.
/// @dev The payment token is fixed by deployment and every stage fee is stored
///      in that token's base units. Unlike V2/V3, this contract has no price
///      oracle, TWAP, quote freshness rule, deadline, or maximum-payment path.
///      A member registers at Stage 1, then `joinStage` enforces enrollment in
///      the immediately preceding stage before unlocking the next one.
contract BinaryMembershipV4 is BinaryMembershipV1 {
    using SafeERC20 for IERC20;

    address public companyWallet;

    error PayoutWalletCollision(address wallet);

    event CompanyWalletUpdated(address indexed oldCompanyWallet, address indexed newCompanyWallet);
    event CompanyProfitWithdrawn(address indexed companyWallet, uint256 amount);
    event TreasuryWithdrawalSplit(uint256 totalAmount, uint256 treasuryAmount, uint256 companyAmount);

    constructor(
        IERC20 _asset,
        address _treasury,
        address _companyWallet,
        address _admin,
        uint48 _adminDelay,
        address _designatedRoot
    ) BinaryMembershipV1(_asset, _treasury, _admin, _adminDelay, _designatedRoot) {
        if (_companyWallet == address(0)) revert ZeroAddress();
        if (_companyWallet == _treasury) revert PayoutWalletCollision(_companyWallet);
        companyWallet = _companyWallet;
    }

    /// @notice Withdraw an accrued treasury amount, split 50/50 between the
    ///         treasury wallet and the company wallet.
    /// @dev For an odd base-unit amount, the treasury receives the indivisible
    ///      remainder so the company side can never exceed half.
    function withdrawTreasury(uint256 amount) external override nonReentrant whenNotPaused onlyRole(TREASURY_ROLE) {
        if (amount > pendingTreasury) {
            revert InsufficientPendingTreasury(pendingTreasury, amount);
        }

        pendingTreasury -= amount;
        uint256 companyAmount = amount / 2;
        uint256 treasuryAmount = amount - companyAmount;

        if (treasuryAmount != 0) asset.safeTransfer(treasury, treasuryAmount);
        if (companyAmount != 0) asset.safeTransfer(companyWallet, companyAmount);

        emit TreasuryWithdrawn(treasury, treasuryAmount);
        emit CompanyProfitWithdrawn(companyWallet, companyAmount);
        emit TreasuryWithdrawalSplit(amount, treasuryAmount, companyAmount);
    }

    function setCompanyWallet(address newCompanyWallet) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newCompanyWallet == address(0)) revert ZeroAddress();
        if (newCompanyWallet == treasury) revert PayoutWalletCollision(newCompanyWallet);

        address oldCompanyWallet = companyWallet;
        companyWallet = newCompanyWallet;
        emit CompanyWalletUpdated(oldCompanyWallet, newCompanyWallet);
    }

    function setTreasury(address newTreasury) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newTreasury == address(0)) revert ZeroAddress();
        if (newTreasury == companyWallet) revert PayoutWalletCollision(newTreasury);

        address oldTreasury = treasury;
        treasury = newTreasury;
        emit TreasuryAddressUpdated(oldTreasury, newTreasury);
    }
}
