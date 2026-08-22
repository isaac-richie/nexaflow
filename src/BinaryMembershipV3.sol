// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {BinaryMembershipV1} from "./BinaryMembershipV1.sol";
import {BinaryMembershipV2} from "./BinaryMembershipV2.sol";
import {IAssetUsdPriceOracle} from "./interfaces/IAssetUsdPriceOracle.sol";

/// @title BinaryMembershipV3
/// @notice RWAAN-priced membership with independently selectable stages.
/// @dev V2 made the stage ladder sequential. V3 keeps its live oracle pricing,
///      max-payment protection, treasury split, and payout rules, but lets a
///      wallet start at (or later add) any stage it has not already joined.
///      The designated protocol root still starts at Stage 1 so the protocol
///      has a canonical first anchor; the operator seeds the higher anchors.
contract BinaryMembershipV3 is BinaryMembershipV2 {
    error RootMustStartAtStageOne();

    constructor(
        IERC20Metadata _asset,
        IAssetUsdPriceOracle _priceOracle,
        uint256 _maxPriceAge,
        address _treasury,
        address _companyWallet,
        address _admin,
        uint48 _adminDelay,
        address _designatedRoot
    )
        BinaryMembershipV2(
            _asset,
            _priceOracle,
            _maxPriceAge,
            _treasury,
            _companyWallet,
            _admin,
            _adminDelay,
            _designatedRoot
        )
    {}

    /// @notice Register a new wallet directly into any selected stage.
    /// @dev The first, designated root remains the sole exception: it must
    ///      open Stage 1 first to establish the protocol's initial anchor.
    ///      Every paid entry supplies a maximum RWAAN debit and deadline.
    function registerAtStageWithMaxPayment(
        uint256 stageId,
        address sponsor,
        address parent,
        Side side,
        uint256 maximumPayment,
        uint256 deadline
    ) external nonReentrant whenNotPaused {
        _checkDeadline(deadline);
        _registerAtStage(stageId, sponsor, parent, side, maximumPayment);
    }

    /// @notice Join any stage the member has not already entered.
    /// @dev This deliberately does not call `_joinStageEntry`, whose previous
    ///      stage check is V2's sequential-ladder policy. Tree placement,
    ///      payment caps, oracle validation and payout accounting still use
    ///      the same `_joinStage` implementation.
    function joinAnyStageWithMaxPayment(
        uint256 stageId,
        address parent,
        Side side,
        uint256 maximumPayment,
        uint256 deadline
    ) external nonReentrant whenNotPaused {
        _checkDeadline(deadline);
        if (!configured) revert StagesNotConfigured();
        if (!members[msg.sender].active) revert NotRegistered();
        if (stageId >= MAX_STAGES) revert InvalidStage(stageId);
        if (stageMemberships[msg.sender][stageId].enrolled) {
            revert AlreadyEnrolledInStage(stageId);
        }

        _joinStage(stageId, parent, side, maximumPayment);
    }

    function _registerAtStage(
        uint256 stageId,
        address sponsor,
        address parent,
        Side side,
        uint256 maximumPayment
    ) internal {
        if (!configured) revert StagesNotConfigured();
        if (stageId >= MAX_STAGES) revert InvalidStage(stageId);
        if (members[msg.sender].active) revert AlreadyRegistered();

        bool isRoot = memberCount == 0;
        if (isRoot) {
            if (msg.sender != designatedRoot) revert NotDesignatedRoot();
            if (stageId != 0) revert RootMustStartAtStageOne();
        } else if (sponsor == address(0) || !members[sponsor].active) {
            revert SponsorNotRegistered();
        }

        memberCount++;
        members[msg.sender] = Member({
            active: true,
            sponsor: isRoot ? address(0) : sponsor,
            joinedAt: uint64(block.timestamp),
            totalEarned: 0
        });

        emit MemberRegistered(msg.sender, sponsor, memberCount);
        _updateWeeklySponsor(sponsor);

        if (isRoot) {
            _enrollRoot(0);
        } else {
            _joinStage(stageId, parent, side, maximumPayment);
        }
    }
}
