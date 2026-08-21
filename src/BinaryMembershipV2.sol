// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BinaryMembershipV1} from "./BinaryMembershipV1.sol";
import {IAssetUsdPriceOracle} from "./interfaces/IAssetUsdPriceOracle.sol";

/// @title BinaryMembershipV2
/// @notice BinaryMembershipV1 paid in a market-priced ERC-20.
/// @dev Stage `fee` and `nodeReward` values are USD amounts with 18 decimals.
///      Each paid enrollment snapshots the oracle once and converts both values
///      into payment-token units. The fee rounds up and the reward rounds down,
///      preserving solvency even at conversion boundaries.
contract BinaryMembershipV2 is BinaryMembershipV1 {
    using SafeERC20 for IERC20;

    IAssetUsdPriceOracle public immutable priceOracle;
    uint256 public immutable assetUnit;
    uint256 public immutable maxPriceAge;
    address public companyWallet;

    error InvalidPrice();
    error StalePrice(uint256 updatedAt, uint256 currentTimestamp);
    error FuturePrice(uint256 updatedAt, uint256 currentTimestamp);
    error MaximumPaymentRequired();
    error TransactionExpired(uint256 deadline, uint256 currentTimestamp);
    error PayoutWalletCollision(address wallet);

    event CompanyWalletUpdated(address indexed oldCompanyWallet, address indexed newCompanyWallet);
    event CompanyProfitWithdrawn(address indexed companyWallet, uint256 amount);
    event TreasuryWithdrawalSplit(uint256 totalAmount, uint256 treasuryAmount, uint256 companyAmount);

    constructor(
        IERC20Metadata _asset,
        IAssetUsdPriceOracle _priceOracle,
        uint256 _maxPriceAge,
        address _treasury,
        address _companyWallet,
        address _admin,
        uint48 _adminDelay,
        address _designatedRoot
    ) BinaryMembershipV1(IERC20(address(_asset)), _treasury, _admin, _adminDelay, _designatedRoot) {
        if (address(_priceOracle) == address(0)) revert ZeroAddress();
        if (_maxPriceAge == 0) revert InvalidPrice();
        if (_companyWallet == address(0)) revert ZeroAddress();
        if (_companyWallet == _treasury) revert PayoutWalletCollision(_companyWallet);

        uint8 assetDecimals = _asset.decimals();
        if (assetDecimals > 36) revert InvalidPrice();

        priceOracle = _priceOracle;
        assetUnit = 10 ** uint256(assetDecimals);
        maxPriceAge = _maxPriceAge;
        companyWallet = _companyWallet;
    }

    /// @notice Withdraw a total amount and split it 50/50 between treasury and
    ///         company. For an odd base-unit amount, treasury receives the one
    ///         indivisible remainder so company profit never exceeds 50%.
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

    /// @notice Current token amounts required for a stage.
    /// @return feeAmount Registration fee in payment-token base units.
    /// @return rewardAmount Per-upline reward in payment-token base units.
    /// @return priceUsd18 USD price of one whole payment token, scaled 1e18.
    /// @return updatedAt Timestamp supplied by the oracle.
    function quoteStagePayment(uint256 stageId)
        external
        view
        returns (uint256 feeAmount, uint256 rewardAmount, uint256 priceUsd18, uint256 updatedAt)
    {
        if (stageId >= MAX_STAGES) revert InvalidStage(stageId);
        (priceUsd18, updatedAt) = _validatedPrice();
        (feeAmount, rewardAmount) = _convertStage(stageId, priceUsd18);
    }

    function latestAssetPriceUsd() external view returns (uint256 priceUsd18, uint256 updatedAt) {
        return _validatedPrice();
    }

    /// @notice The free, designated root may use the legacy registration ABI.
    /// @dev Every paid V2 registration must use `registerWithMaxPayment`, so an
    ///      unlimited ERC-20 allowance cannot turn oracle movement into an
    ///      uncapped debit.
    function register(address sponsor, address parent, Side side) external override nonReentrant whenNotPaused {
        if (memberCount != 0) revert MaximumPaymentRequired();
        _register(sponsor, parent, side, type(uint256).max);
    }

    /// @notice Register and cap the RWAAN amount the transaction may spend.
    /// @param maximumPayment Maximum RWAAN base units the caller accepts.
    function registerWithMaxPayment(
        address sponsor,
        address parent,
        Side side,
        uint256 maximumPayment,
        uint256 deadline
    ) external nonReentrant whenNotPaused {
        _checkDeadline(deadline);
        _register(sponsor, parent, side, maximumPayment);
    }

    /// @dev Paid V2 joins must use the bounded entrypoint below.
    function joinStage(uint256, address, Side) external override nonReentrant whenNotPaused {
        revert MaximumPaymentRequired();
    }

    /// @notice Join a later stage and cap the RWAAN amount that may be spent.
    function joinStageWithMaxPayment(
        uint256 stageId,
        address parent,
        Side side,
        uint256 maximumPayment,
        uint256 deadline
    ) external nonReentrant whenNotPaused {
        _checkDeadline(deadline);
        _joinStageEntry(stageId, parent, side, maximumPayment);
    }

    function _checkDeadline(uint256 deadline) internal view {
        if (block.timestamp > deadline) revert TransactionExpired(deadline, block.timestamp);
    }

    function _stagePaymentAmounts(uint256 stageId)
        internal
        view
        override
        returns (uint256 feeAmount, uint256 rewardAmount)
    {
        (uint256 priceUsd18,) = _validatedPrice();
        return _convertStage(stageId, priceUsd18);
    }

    function _convertStage(uint256 stageId, uint256 priceUsd18)
        internal
        view
        returns (uint256 feeAmount, uint256 rewardAmount)
    {
        StageConfig storage config = stages[stageId];

        feeAmount = Math.mulDiv(config.fee, assetUnit, priceUsd18, Math.Rounding.Ceil);
        rewardAmount = Math.mulDiv(config.nodeReward, assetUnit, priceUsd18);

        // Rounding must never turn a valid USD configuration insolvent.
        if (feeAmount == 0 || rewardAmount == 0 || rewardAmount * config.treeDepth >= feeAmount) {
            revert InvalidFeeConfig();
        }
    }

    function _validatedPrice() internal view returns (uint256 priceUsd18, uint256 updatedAt) {
        (priceUsd18, updatedAt) = priceOracle.latestPriceUsd();
        if (priceUsd18 == 0 || updatedAt == 0) revert InvalidPrice();
        if (updatedAt > block.timestamp) revert FuturePrice(updatedAt, block.timestamp);
        if (block.timestamp - updatedAt > maxPriceAge) revert StalePrice(updatedAt, block.timestamp);
    }
}
