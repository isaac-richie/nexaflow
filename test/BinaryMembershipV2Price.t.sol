// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {BinaryMembershipV2} from "../src/BinaryMembershipV2.sol";
import {MockAssetUsdPriceOracle} from "../src/MockAssetUsdPriceOracle.sol";
import {MockERC20} from "../src/MockERC20.sol";

contract BinaryMembershipV2PriceTest is Test {
    uint256 internal constant RWAAN_PRICE = 0.0001 ether;
    uint256 internal constant MAX_PRICE_AGE = 2 hours;

    address internal constant ADMIN = address(0xA11CE);
    address internal constant TREASURY = address(0x7000);
    address internal constant COMPANY = address(0x8000);
    address internal constant ROOT = address(0x1000);
    address internal constant ALICE = address(0x2000);
    address internal constant BOB = address(0x3000);

    MockERC20 internal rwaan;
    MockAssetUsdPriceOracle internal oracle;
    BinaryMembershipV2 internal membership;

    function setUp() public {
        vm.warp(10 days);
        rwaan = new MockERC20("Rawli Analytics", "RWAAN", 18);
        oracle = new MockAssetUsdPriceOracle(RWAAN_PRICE);
        membership = new BinaryMembershipV2(
            IERC20Metadata(address(rwaan)), oracle, MAX_PRICE_AGE, TREASURY, COMPANY, ADMIN, 0, ROOT
        );

        vm.prank(ADMIN);
        membership.configureStages(
            [uint256(20 ether), 60 ether, 180 ether, 540 ether, 1_620 ether, 4_860 ether],
            [uint256(5 ether), 10 ether, 25 ether, 80 ether, 250 ether, 800 ether],
            [uint256(6), 14, 14, 14, 14, 14],
            [uint256(2), 3, 3, 3, 3, 3],
            [uint256(0), 10, 10, 10, 10, 8]
        );

        vm.prank(ROOT);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);

        _fundAndApprove(ALICE);
        _fundAndApprove(BOB);
    }

    function test_QuoteConvertsUsdStageValuesToRwaan() public view {
        (uint256 fee, uint256 reward, uint256 price, uint256 updatedAt) = membership.quoteStagePayment(0);

        assertEq(fee, 200_000 ether);
        assertEq(reward, 50_000 ether);
        assertEq(price, RWAAN_PRICE);
        assertEq(updatedAt, block.timestamp);
    }

    function test_RegistrationUsesCurrentPriceForFeeRewardAndTreasury() public {
        uint256 aliceBefore = rwaan.balanceOf(ALICE);

        vm.prank(ALICE);
        membership.registerWithMaxPayment(
            ROOT, ROOT, BinaryMembershipV1.Side.Left, 200_000 ether, block.timestamp + 1 hours
        );

        assertEq(aliceBefore - rwaan.balanceOf(ALICE), 200_000 ether);
        assertEq(rwaan.balanceOf(ROOT), 50_000 ether);
        assertEq(membership.pendingTreasury(), 150_000 ether);
        assertEq(membership.totalPoolPaid(), 50_000 ether);
        assertEq(membership.totalTreasuryPaid(), 150_000 ether);
    }

    function test_LaterRegistrationUsesNewMarketPrice() public {
        vm.prank(ALICE);
        membership.registerWithMaxPayment(
            ROOT, ROOT, BinaryMembershipV1.Side.Left, 200_000 ether, block.timestamp + 1 hours
        );

        oracle.setPrice(0.0002 ether);
        uint256 bobBefore = rwaan.balanceOf(BOB);

        vm.prank(BOB);
        membership.registerWithMaxPayment(
            ROOT, ROOT, BinaryMembershipV1.Side.Right, 100_000 ether, block.timestamp + 1 hours
        );

        assertEq(bobBefore - rwaan.balanceOf(BOB), 100_000 ether);
        assertEq(rwaan.balanceOf(ROOT), 75_000 ether); // 50k at old price + 25k now
        assertEq(membership.pendingTreasury(), 225_000 ether); // 150k + 75k
    }

    function test_FeeRoundsUpAndRewardRoundsDown() public {
        oracle.setPrice(3 ether);

        (uint256 fee, uint256 reward,,) = membership.quoteStagePayment(0);
        assertEq(fee, 6_666_666_666_666_666_667);
        assertEq(reward, 1_666_666_666_666_666_666);
        assertLt(reward * 2, fee);
    }

    function test_RevertWhenPriceIsStale() public {
        uint256 staleAt = block.timestamp - MAX_PRICE_AGE - 1;
        oracle.setRound(RWAAN_PRICE, staleAt);

        vm.expectRevert(abi.encodeWithSelector(BinaryMembershipV2.StalePrice.selector, staleAt, block.timestamp));
        vm.prank(ALICE);
        membership.registerWithMaxPayment(
            ROOT, ROOT, BinaryMembershipV1.Side.Left, type(uint256).max, block.timestamp + 1 hours
        );
    }

    function test_RevertWhenPriceTimestampIsInFuture() public {
        oracle.setRound(RWAAN_PRICE, block.timestamp + 1);

        vm.expectRevert(
            abi.encodeWithSelector(BinaryMembershipV2.FuturePrice.selector, block.timestamp + 1, block.timestamp)
        );
        membership.quoteStagePayment(0);
    }

    function test_RevertWhenPriceIsZero() public {
        oracle.setPrice(0);

        vm.expectRevert(BinaryMembershipV2.InvalidPrice.selector);
        membership.quoteStagePayment(0);
    }

    function test_RevertWhenConvertedRewardRoundsToZero() public {
        oracle.setPrice(type(uint256).max);

        vm.expectRevert(BinaryMembershipV1.InvalidFeeConfig.selector);
        membership.quoteStagePayment(0);
    }

    function test_RevertWhenPaidRegistrationUsesLegacyUnboundedEntrypoint() public {
        vm.expectRevert(BinaryMembershipV2.MaximumPaymentRequired.selector);
        vm.prank(ALICE);
        membership.register(ROOT, ROOT, BinaryMembershipV1.Side.Left);
    }

    function test_RevertWhenPriceMoveMakesFeeExceedMaximum() public {
        (uint256 quotedFee,,,) = membership.quoteStagePayment(0);
        oracle.setPrice(0.00005 ether); // token price halves, required tokens double

        vm.expectRevert(
            abi.encodeWithSelector(BinaryMembershipV1.PaymentExceedsMaximum.selector, 400_000 ether, quotedFee)
        );
        vm.prank(ALICE);
        membership.registerWithMaxPayment(
            ROOT, ROOT, BinaryMembershipV1.Side.Left, quotedFee, block.timestamp + 1 hours
        );

        (bool active,,,) = membership.members(ALICE);
        assertFalse(active);
        assertEq(rwaan.balanceOf(address(membership)), 0);
    }

    function test_PriceImprovementChargesLessThanMaximum() public {
        (uint256 quotedFee,,,) = membership.quoteStagePayment(0);
        oracle.setPrice(0.0002 ether); // token price doubles, required tokens halve
        uint256 beforeBalance = rwaan.balanceOf(ALICE);

        vm.prank(ALICE);
        membership.registerWithMaxPayment(
            ROOT, ROOT, BinaryMembershipV1.Side.Left, quotedFee, block.timestamp + 1 hours
        );

        assertEq(beforeBalance - rwaan.balanceOf(ALICE), 100_000 ether);
    }

    function test_LaterStageAlsoRequiresAndHonorsMaximumPayment() public {
        vm.startPrank(ADMIN);
        membership.grantRole(membership.OPERATOR_ROLE(), ADMIN);
        membership.enrollStageRoot(ROOT, 1);
        vm.stopPrank();

        vm.prank(ALICE);
        membership.registerWithMaxPayment(
            ROOT, ROOT, BinaryMembershipV1.Side.Left, 200_000 ether, block.timestamp + 1 hours
        );

        (uint256 stageFee,,,) = membership.quoteStagePayment(1);
        vm.expectRevert(BinaryMembershipV2.MaximumPaymentRequired.selector);
        vm.prank(ALICE);
        membership.joinStage(1, ROOT, BinaryMembershipV1.Side.Left);

        vm.expectRevert(
            abi.encodeWithSelector(BinaryMembershipV1.PaymentExceedsMaximum.selector, stageFee, stageFee - 1)
        );
        vm.prank(ALICE);
        membership.joinStageWithMaxPayment(
            1, ROOT, BinaryMembershipV1.Side.Left, stageFee - 1, block.timestamp + 1 hours
        );

        uint256 beforeBalance = rwaan.balanceOf(ALICE);
        vm.prank(ALICE);
        membership.joinStageWithMaxPayment(1, ROOT, BinaryMembershipV1.Side.Left, stageFee, block.timestamp + 1 hours);
        assertEq(beforeBalance - rwaan.balanceOf(ALICE), stageFee);
    }

    function test_RevertWhenBoundedRegistrationDeadlineExpired() public {
        uint256 deadline = block.timestamp - 1;
        vm.expectRevert(
            abi.encodeWithSelector(BinaryMembershipV2.TransactionExpired.selector, deadline, block.timestamp)
        );
        vm.prank(ALICE);
        membership.registerWithMaxPayment(ROOT, ROOT, BinaryMembershipV1.Side.Left, type(uint256).max, deadline);
    }

    function _fundAndApprove(address user) internal {
        rwaan.mint(user, 10_000_000 ether);
        vm.prank(user);
        rwaan.approve(address(membership), type(uint256).max);
    }
}
