// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {BinaryMembershipV3} from "../src/BinaryMembershipV3.sol";
import {MockAssetUsdPriceOracle} from "../src/MockAssetUsdPriceOracle.sol";
import {MockERC20} from "../src/MockERC20.sol";

contract BinaryMembershipV3FlexibleEntryTest is Test {
    uint256 internal constant UNIT = 1 ether;
    uint256 internal constant PRICE = 0.0001 ether;

    address internal constant ADMIN = address(0xA11CE);
    address internal constant ROOT = address(0x1000);
    address internal constant ALICE = address(0x2000);
    address internal constant BOB = address(0x3000);
    address internal constant TREASURY = address(0x7000);
    address internal constant COMPANY = address(0x8000);

    MockERC20 internal rwaan;
    MockAssetUsdPriceOracle internal oracle;
    BinaryMembershipV3 internal membership;

    function setUp() public {
        vm.warp(10 days);
        rwaan = new MockERC20("Rawli Analytics", "RWAAN", 0);
        oracle = new MockAssetUsdPriceOracle(PRICE);
        membership = new BinaryMembershipV3(
            IERC20Metadata(address(rwaan)), oracle, 2 hours, TREASURY, COMPANY, ADMIN, 0, ROOT
        );

        vm.startPrank(ADMIN);
        membership.configureStages(
            [uint256(20 * UNIT), 60 * UNIT, 180 * UNIT, 540 * UNIT, 1_620 * UNIT, 4_860 * UNIT],
            [uint256(5 * UNIT), 10 * UNIT, 25 * UNIT, 80 * UNIT, 250 * UNIT, 800 * UNIT],
            [uint256(6), 14, 14, 14, 14, 14],
            [uint256(2), 3, 3, 3, 3, 3],
            [uint256(0), 10, 10, 10, 10, 8]
        );
        membership.grantRole(membership.OPERATOR_ROLE(), ADMIN);
        vm.stopPrank();

        vm.prank(ROOT);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);

        vm.startPrank(ADMIN);
        for (uint256 stageId = 1; stageId < membership.MAX_STAGES(); stageId++) {
            membership.enrollStageRoot(ROOT, stageId);
        }
        vm.stopPrank();

        rwaan.mint(ALICE, 100_000_000 * UNIT);
        rwaan.mint(BOB, 100_000_000 * UNIT);
        vm.prank(ALICE);
        rwaan.approve(address(membership), type(uint256).max);
        vm.prank(BOB);
        rwaan.approve(address(membership), type(uint256).max);
    }

    function test_NewWalletCanStartAtAnyStage() public {
        uint256 stageId = 4; // displayed as Stage 5
        (address parent, BinaryMembershipV1.Side side) = membership.findPlacementSlot(ROOT, stageId);
        (uint256 fee,,,) = membership.quoteStagePayment(stageId);

        vm.prank(ALICE);
        membership.registerAtStageWithMaxPayment(stageId, ROOT, parent, side, fee, block.timestamp + 1 hours);

        (bool active, address sponsor,,) = membership.members(ALICE);
        assertTrue(active, "member not registered");
        assertEq(sponsor, ROOT, "wrong sponsor");
        assertTrue(membership.getStageMembership(ALICE, stageId).enrolled, "selected stage not joined");
        assertFalse(membership.getStageMembership(ALICE, 0).enrolled, "stage 1 joined unexpectedly");
        assertFalse(membership.getStageMembership(ALICE, 3).enrolled, "lower stage joined unexpectedly");
        assertEq(rwaan.balanceOf(ALICE), 100_000_000 * UNIT - fee, "wrong RWAAN debit");
    }

    function test_ExistingMemberCanAddAnyUnjoinedStage() public {
        uint256 firstStage = 2;
        (address firstParent, BinaryMembershipV1.Side firstSide) = membership.findPlacementSlot(ROOT, firstStage);
        (uint256 firstFee,,,) = membership.quoteStagePayment(firstStage);
        vm.prank(ALICE);
        membership.registerAtStageWithMaxPayment(
            firstStage, ROOT, firstParent, firstSide, firstFee, block.timestamp + 1 hours
        );

        uint256 secondStage = 0;
        (address secondParent, BinaryMembershipV1.Side secondSide) = membership.findPlacementSlot(ROOT, secondStage);
        (uint256 secondFee,,,) = membership.quoteStagePayment(secondStage);
        vm.prank(ALICE);
        membership.joinAnyStageWithMaxPayment(
            secondStage, secondParent, secondSide, secondFee, block.timestamp + 1 hours
        );

        assertTrue(membership.getStageMembership(ALICE, firstStage).enrolled, "first choice missing");
        assertTrue(membership.getStageMembership(ALICE, secondStage).enrolled, "later choice missing");
        assertFalse(membership.getStageMembership(ALICE, 1).enrolled, "unselected stage joined");
    }

    function test_RootCannotStartAtAHigherStage() public {
        MockERC20 cleanToken = new MockERC20("Rawli Analytics", "RWAAN", 0);
        BinaryMembershipV3 cleanMembership = new BinaryMembershipV3(
            IERC20Metadata(address(cleanToken)), oracle, 2 hours, TREASURY, COMPANY, ADMIN, 0, ROOT
        );
        vm.prank(ADMIN);
        cleanMembership.configureStages(
            [uint256(20 * UNIT), 60 * UNIT, 180 * UNIT, 540 * UNIT, 1_620 * UNIT, 4_860 * UNIT],
            [uint256(5 * UNIT), 10 * UNIT, 25 * UNIT, 80 * UNIT, 250 * UNIT, 800 * UNIT],
            [uint256(6), 14, 14, 14, 14, 14],
            [uint256(2), 3, 3, 3, 3, 3],
            [uint256(0), 10, 10, 10, 10, 8]
        );

        vm.expectRevert(BinaryMembershipV3.RootMustStartAtStageOne.selector);
        vm.prank(ROOT);
        cleanMembership.registerAtStageWithMaxPayment(
            1, address(0), address(0), BinaryMembershipV1.Side.None, 0, block.timestamp + 1 hours
        );
    }

    function test_IndependentEntryStillHonorsQuotedMaximum() public {
        uint256 stageId = 5;
        (address parent, BinaryMembershipV1.Side side) = membership.findPlacementSlot(ROOT, stageId);
        (uint256 quote,,,) = membership.quoteStagePayment(stageId);
        oracle.setPrice(PRICE / 2); // halving price doubles the required RWAAN

        vm.expectRevert(
            abi.encodeWithSelector(BinaryMembershipV1.PaymentExceedsMaximum.selector, quote * 2, quote)
        );
        vm.prank(BOB);
        membership.registerAtStageWithMaxPayment(stageId, ROOT, parent, side, quote, block.timestamp + 1 hours);

        (bool active,,,) = membership.members(BOB);
        assertFalse(active, "failed capped transaction registered member");
    }
}
