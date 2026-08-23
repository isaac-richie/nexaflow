// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {BinaryMembershipV4} from "../src/BinaryMembershipV4.sol";
import {MockUSDT18} from "../src/MockUSDT18.sol";

contract BinaryMembershipV4UsdtTest is Test {
    uint256 internal constant UNIT = 1e18;

    address internal constant ADMIN = address(0xA11CE);
    address internal constant ROOT = address(0x1000);
    address internal constant ALICE = address(0x2000);
    address internal constant BOB = address(0x3000);
    address internal constant TREASURY = address(0x7000);
    address internal constant COMPANY = address(0x8000);

    MockUSDT18 internal usdt;
    BinaryMembershipV4 internal membership;

    function setUp() public {
        usdt = new MockUSDT18(ADMIN);
        membership = new BinaryMembershipV4(IERC20(address(usdt)), TREASURY, COMPANY, ADMIN, 0, ROOT);

        vm.startPrank(ADMIN);
        membership.configureStages(
            [uint256(20 * UNIT), 60 * UNIT, 180 * UNIT, 540 * UNIT, 1_620 * UNIT, 4_860 * UNIT],
            [uint256(5 * UNIT), 10 * UNIT, 25 * UNIT, 80 * UNIT, 250 * UNIT, 800 * UNIT],
            [uint256(6), 14, 14, 14, 14, 14],
            [uint256(2), 3, 3, 3, 3, 3],
            [uint256(0), 10, 10, 10, 10, 8]
        );
        membership.grantRole(membership.OPERATOR_ROLE(), ADMIN);
        membership.grantRole(membership.TREASURY_ROLE(), ADMIN);
        vm.stopPrank();

        vm.prank(ROOT);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);

        vm.prank(ADMIN);
        membership.enrollStageRoot(ROOT, 1);

        vm.prank(ADMIN);
        usdt.mint(ALICE, 10_000 * UNIT);
        vm.prank(ALICE);
        usdt.approve(address(membership), type(uint256).max);
    }

    function test_StageOneMustBeJoinedBeforeStageTwo() public {
        vm.expectRevert(abi.encodeWithSelector(BinaryMembershipV1.NotRegistered.selector));
        vm.prank(ALICE);
        membership.joinStage(1, ROOT, BinaryMembershipV1.Side.Left);

        vm.prank(ALICE);
        membership.register(ROOT, ROOT, BinaryMembershipV1.Side.Left);
        assertTrue(membership.getStageMembership(ALICE, 0).enrolled, "stage 1 not joined");

        (address parent, BinaryMembershipV1.Side side) = membership.findPlacementSlot(ROOT, 1);
        vm.prank(ALICE);
        membership.joinStage(1, parent, side);
        assertTrue(membership.getStageMembership(ALICE, 1).enrolled, "stage 2 not joined");
    }

    function test_FixedUsdtFeesAndRewardsAreUsedWithoutAnOracle() public {
        uint256 aliceBefore = usdt.balanceOf(ALICE);
        vm.prank(ALICE);
        membership.register(ROOT, ROOT, BinaryMembershipV1.Side.Left);

        assertEq(aliceBefore - usdt.balanceOf(ALICE), 20 * UNIT, "wrong Stage 1 USDT fee");
        assertEq(usdt.balanceOf(ROOT), 5 * UNIT, "wrong immediate USDT reward");
        assertEq(membership.pendingTreasury(), 15 * UNIT, "wrong treasury allocation");
    }

    function test_TreasuryWithdrawalSplitsExactlyFiftyFifty() public {
        vm.prank(ALICE);
        membership.register(ROOT, ROOT, BinaryMembershipV1.Side.Left);

        uint256 treasuryBefore = usdt.balanceOf(TREASURY);
        uint256 companyBefore = usdt.balanceOf(COMPANY);
        vm.prank(ADMIN);
        membership.withdrawTreasury(15 * UNIT);

        assertEq(usdt.balanceOf(TREASURY) - treasuryBefore, (15 * UNIT) / 2, "wrong treasury half");
        assertEq(usdt.balanceOf(COMPANY) - companyBefore, (15 * UNIT) / 2, "wrong company half");
        assertEq(membership.pendingTreasury(), 0, "pending treasury not cleared");
    }

    function test_PayoutWalletsCannotCollide() public {
        vm.expectRevert(abi.encodeWithSelector(BinaryMembershipV4.PayoutWalletCollision.selector, TREASURY));
        new BinaryMembershipV4(IERC20(address(usdt)), TREASURY, TREASURY, ADMIN, 0, ROOT);

        vm.expectRevert(abi.encodeWithSelector(BinaryMembershipV4.PayoutWalletCollision.selector, TREASURY));
        vm.prank(ADMIN);
        membership.setCompanyWallet(TREASURY);

        vm.expectRevert(abi.encodeWithSelector(BinaryMembershipV4.PayoutWalletCollision.selector, COMPANY));
        vm.prank(ADMIN);
        membership.setTreasury(COMPANY);
    }
}
