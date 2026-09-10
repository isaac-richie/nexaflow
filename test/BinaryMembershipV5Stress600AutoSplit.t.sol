// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {BinaryMembershipV5} from "../src/BinaryMembershipV5.sol";
import {MockUSDT18} from "../src/MockUSDT18.sol";

/// @notice 600-wallet full-ladder campaign validating immediate 50/50
/// treasury/company distribution, spillover, spillunder, rollovers, and
/// per-member accounting.
contract BinaryMembershipV5Stress600AutoSplitTest is Test {
    uint256 internal constant UNIT = 1e18;
    uint256 internal constant WALLET_COUNT = 600;
    uint256 internal constant PAYING_COUNT = WALLET_COUNT - 1;

    address internal constant ADMIN = address(0xA11CE);
    address internal constant ROOT = address(0x1000);
    address internal constant TREASURY = address(0x7000);
    address internal constant COMPANY = address(0x8000);

    MockUSDT18 internal usdt;
    BinaryMembershipV5 internal membership;
    address[PAYING_COUNT] internal wallets;

    uint256[6] internal fees = [uint256(20 * UNIT), 60 * UNIT, 180 * UNIT, 540 * UNIT, 1_620 * UNIT, 4_860 * UNIT];
    uint256[6] internal rewards = [uint256(5 * UNIT), 10 * UNIT, 25 * UNIT, 80 * UNIT, 250 * UNIT, 800 * UNIT];

    function setUp() public {
        usdt = new MockUSDT18(ADMIN);
        membership = new BinaryMembershipV5(IERC20(address(usdt)), TREASURY, COMPANY, ADMIN, 0, ROOT);

        vm.startPrank(ADMIN);
        membership.configureStages(
            fees,
            rewards,
            [uint256(6), 14, 14, 14, 14, 14],
            [uint256(2), 3, 3, 3, 3, 3],
            [uint256(0), 10, 10, 10, 10, 8]
        );
        membership.grantRole(membership.OPERATOR_ROLE(), ADMIN);
        membership.setCycleGuardEnabled(true);
        vm.stopPrank();

        vm.prank(ROOT);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);

        vm.startPrank(ADMIN);
        for (uint256 stageId = 1; stageId < 6; stageId++) {
            membership.enrollStageRoot(ROOT, stageId);
        }
        vm.stopPrank();

        for (uint256 i; i < PAYING_COUNT; i++) {
            address wallet = address(uint160(0x600000 + i));
            wallets[i] = wallet;
            vm.prank(ADMIN);
            usdt.mint(wallet, 10_000 * UNIT);
            vm.prank(wallet);
            usdt.approve(address(membership), type(uint256).max);
        }
    }

    function test_600Wallets_AllStages_AutoSplitAndBoardLogic() public {
        uint256[6] memory stageTreasury;
        uint256[6] memory spillovers;

        for (uint256 stageId; stageId < 6; stageId++) {
            uint256 poolBefore = membership.totalPoolPaid();
            uint256 treasuryBefore = membership.totalTreasuryPaid();

            for (uint256 i; i < PAYING_COUNT; i++) {
                (address parent, BinaryMembershipV1.Side side) = membership.findPlacementSlot(ROOT, stageId);
                if (parent != ROOT) spillovers[stageId]++;

                vm.prank(wallets[i]);
                if (stageId == 0) membership.register(ROOT, parent, side);
                else membership.joinStage(stageId, parent, side);
            }

            uint256 stageFees = PAYING_COUNT * fees[stageId];
            uint256 stagePool = membership.totalPoolPaid() - poolBefore;
            stageTreasury[stageId] = membership.totalTreasuryPaid() - treasuryBefore;

            assertEq(stagePool + stageTreasury[stageId], stageFees, "stage conservation");
            assertGt(spillovers[stageId], 0, "stage did not spill over");
            assertGt(membership.getStageMembership(ROOT, stageId).rolloverCount, 0, "root did not roll over");
            assertEq(membership.pendingTreasury(), 0, "entry funds left pending");
            assertEq(usdt.balanceOf(address(membership)), 0, "entry funds retained by contract");
        }

        assertEq(membership.memberCount(), WALLET_COUNT, "wrong member count");
        _assertAllWalletsUnlockedAndSpillunder();

        uint256 totalFees;
        uint256 totalTreasury;
        for (uint256 stageId; stageId < 6; stageId++) {
            totalFees += PAYING_COUNT * fees[stageId];
            totalTreasury += stageTreasury[stageId];
        }

        uint256 expectedCompany = totalTreasury / 2;
        uint256 expectedTreasury = totalTreasury - expectedCompany;
        assertEq(membership.totalPoolPaid() + membership.totalTreasuryPaid(), totalFees, "global conservation");
        assertEq(usdt.balanceOf(TREASURY), expectedTreasury, "wrong auto treasury total");
        assertEq(usdt.balanceOf(COMPANY), expectedCompany, "wrong auto company total");
        assertEq(membership.pendingTreasury(), 0, "pending treasury remains");
        assertEq(usdt.balanceOf(address(membership)), 0, "contract retains USDT");

        console2.log("=== V5 600-wallet automatic USDT split results ===");
        console2.log("total entry fees (USDT)", totalFees / UNIT);
        console2.log("paid to members (USDT)", membership.totalPoolPaid() / UNIT);
        console2.log("auto-split total (USDT)", totalTreasury / UNIT);
        console2.log("treasury wallet share (USDT)", expectedTreasury / UNIT);
        console2.log("company wallet share (USDT)", expectedCompany / UNIT);
    }

    function test_EntryRemainderIsSplitImmediatelyAndWalletUpdatesTakeEffect() public {
        address first = wallets[0];
        (address parent, BinaryMembershipV1.Side side) = membership.findPlacementSlot(ROOT, 0);

        vm.prank(first);
        membership.register(ROOT, parent, side);

        // Stage 1 pays the root 5 USDT and splits the 15 USDT remainder.
        assertEq(usdt.balanceOf(ROOT), 5 * UNIT, "root reward mismatch");
        assertEq(usdt.balanceOf(TREASURY), 7.5 ether, "treasury did not receive immediately");
        assertEq(usdt.balanceOf(COMPANY), 7.5 ether, "company did not receive immediately");
        assertEq(membership.pendingTreasury(), 0, "entry remainder was retained");
        assertEq(usdt.balanceOf(address(membership)), 0, "contract retained entry funds");

        address newTreasury = address(0x7001);
        address newCompany = address(0x8001);
        vm.startPrank(ADMIN);
        membership.setTreasury(newTreasury);
        membership.setCompanyWallet(newCompany);
        vm.stopPrank();

        uint256 oldTreasuryBalance = usdt.balanceOf(TREASURY);
        uint256 oldCompanyBalance = usdt.balanceOf(COMPANY);
        address second = wallets[1];
        (parent, side) = membership.findPlacementSlot(ROOT, 0);
        vm.prank(second);
        membership.register(ROOT, parent, side);

        assertEq(usdt.balanceOf(TREASURY), oldTreasuryBalance, "old treasury still received funds");
        assertEq(usdt.balanceOf(COMPANY), oldCompanyBalance, "old company still received funds");
        assertEq(usdt.balanceOf(newTreasury), 7.5 ether, "new treasury was not used");
        assertEq(usdt.balanceOf(newCompany), 7.5 ether, "new company was not used");
    }

    function test_OddBaseUnitRemainderGoesToTreasury() public {
        vm.prank(ADMIN);
        membership.updateStageFee(0, fees[0] + 1, rewards[0]);

        (address parent, BinaryMembershipV1.Side side) = membership.findPlacementSlot(ROOT, 0);
        vm.prank(wallets[0]);
        membership.register(ROOT, parent, side);

        uint256 remainder = fees[0] + 1 - rewards[0];
        assertEq(usdt.balanceOf(TREASURY), remainder - (remainder / 2), "odd unit not assigned to treasury");
        assertEq(usdt.balanceOf(COMPANY), remainder / 2, "company received more than half");
        assertEq(usdt.balanceOf(address(membership)), 0, "contract retained entry funds");
    }

    function test_ExternallyFundedAwardReserveStaysSeparate() public {
        uint256 reserve = 100 * UNIT;
        vm.prank(ADMIN);
        usdt.mint(ADMIN, reserve);
        vm.startPrank(ADMIN);
        usdt.approve(address(membership), reserve);
        membership.fundTreasury(reserve);
        vm.stopPrank();

        (address parent, BinaryMembershipV1.Side side) = membership.findPlacementSlot(ROOT, 0);
        vm.prank(wallets[0]);
        membership.register(ROOT, parent, side);

        assertEq(membership.pendingTreasury(), reserve, "award reserve accounting changed");
        assertEq(usdt.balanceOf(address(membership)), reserve, "award reserve left contract");
        assertEq(usdt.balanceOf(TREASURY), 7.5 ether, "entry split did not reach treasury");
        assertEq(usdt.balanceOf(COMPANY), 7.5 ether, "entry split did not reach company");
    }

    function _assertAllWalletsUnlockedAndSpillunder() internal view {
        uint256[6] memory spillunderEarners;
        for (uint256 i; i < PAYING_COUNT; i++) {
            uint256 walletEarnings;
            for (uint256 stageId; stageId < 6; stageId++) {
                BinaryMembershipV1.StageMembership memory stage = membership.getStageMembership(wallets[i], stageId);
                assertTrue(stage.enrolled, "wallet missed sequential stage");
                assertLe(stage.slotsFilledBelow, membership.getStageConfig(stageId).treeSlots, "board overfilled");
                walletEarnings += stage.stageEarnings;
                if (stage.stageEarnings > 0) spillunderEarners[stageId]++;
            }
            assertEq(membership.getMember(wallets[i]).totalEarned, walletEarnings, "member ledger mismatch");
        }

        for (uint256 stageId; stageId < 6; stageId++) {
            assertGt(spillunderEarners[stageId], 0, "stage had no spillunder earner");
        }
    }
}
