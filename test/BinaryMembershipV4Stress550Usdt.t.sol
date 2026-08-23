// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {BinaryMembershipV4} from "../src/BinaryMembershipV4.sol";
import {MockUSDT18} from "../src/MockUSDT18.sol";

/// @notice Full USDT-path campaign: 550 total wallets (root + 549 payers),
///         every paid wallet unlocks all six stages in order.
contract BinaryMembershipV4Stress550UsdtTest is Test {
    uint256 internal constant UNIT = 1e18;
    uint256 internal constant WALLET_COUNT = 550;
    uint256 internal constant PAYING_COUNT = WALLET_COUNT - 1;

    address internal constant ADMIN = address(0xA11CE);
    address internal constant ROOT = address(0x1000);
    address internal constant TREASURY = address(0x7000);
    address internal constant COMPANY = address(0x8000);
    address internal constant NEW_TREASURY = address(0x9000);
    address internal constant NEW_COMPANY = address(0xA000);

    MockUSDT18 internal usdt;
    BinaryMembershipV4 internal membership;
    address[PAYING_COUNT] internal wallets;

    uint256[6] internal fees = [uint256(20 * UNIT), 60 * UNIT, 180 * UNIT, 540 * UNIT, 1_620 * UNIT, 4_860 * UNIT];
    uint256[6] internal rewards = [uint256(5 * UNIT), 10 * UNIT, 25 * UNIT, 80 * UNIT, 250 * UNIT, 800 * UNIT];

    function setUp() public {
        usdt = new MockUSDT18(ADMIN);
        membership = new BinaryMembershipV4(IERC20(address(usdt)), TREASURY, COMPANY, ADMIN, 0, ROOT);

        vm.startPrank(ADMIN);
        membership.configureStages(
            fees,
            rewards,
            [uint256(6), 14, 14, 14, 14, 14],
            [uint256(2), 3, 3, 3, 3, 3],
            [uint256(0), 10, 10, 10, 10, 8]
        );
        membership.grantRole(membership.OPERATOR_ROLE(), ADMIN);
        membership.grantRole(membership.TREASURY_ROLE(), ADMIN);
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
            address wallet = address(uint160(0x550000 + i));
            wallets[i] = wallet;
            vm.prank(ADMIN);
            usdt.mint(wallet, 10_000 * UNIT);
            vm.prank(wallet);
            usdt.approve(address(membership), type(uint256).max);
        }
    }

    function test_550Wallets_AllStages_UsdtPayoutsAndTreasurySplit() public {
        uint256[6] memory stageFees;
        uint256[6] memory stagePool;
        uint256[6] memory stageTreasury;
        uint256[6] memory spillovers;

        for (uint256 stageId; stageId < 6; stageId++) {
            uint256 poolBefore = membership.totalPoolPaid();
            uint256 treasuryBefore = membership.totalTreasuryPaid();

            for (uint256 i; i < PAYING_COUNT; i++) {
                (address parent, BinaryMembershipV1.Side side) = membership.findPlacementSlot(ROOT, stageId);
                if (parent != ROOT) spillovers[stageId]++;

                vm.prank(wallets[i]);
                if (stageId == 0) {
                    membership.register(ROOT, parent, side);
                } else {
                    membership.joinStage(stageId, parent, side);
                }
            }

            stageFees[stageId] = PAYING_COUNT * fees[stageId];
            stagePool[stageId] = membership.totalPoolPaid() - poolBefore;
            stageTreasury[stageId] = membership.totalTreasuryPaid() - treasuryBefore;

            assertEq(stagePool[stageId] + stageTreasury[stageId], stageFees[stageId], "stage conservation");
            assertGt(spillovers[stageId], 0, "stage did not spill over");
            assertGt(membership.getStageMembership(ROOT, stageId).rolloverCount, 0, "root did not roll over");
        }

        assertEq(membership.memberCount(), WALLET_COUNT, "wrong member count");
        _assertAllWalletsUnlockedAndSpillunder();

        uint256 totalFees;
        uint256 totalTreasury;
        for (uint256 stageId; stageId < 6; stageId++) {
            totalFees += stageFees[stageId];
            totalTreasury += stageTreasury[stageId];
        }
        assertEq(membership.totalPoolPaid() + membership.totalTreasuryPaid(), totalFees, "global conservation");
        assertEq(membership.pendingTreasury(), totalTreasury, "treasury liability mismatch");
        assertEq(usdt.balanceOf(address(membership)), totalTreasury, "USDT balance mismatch");

        console2.log("=== V4 550-wallet USDT results ===");
        console2.log("total entry fees (USDT)", totalFees / UNIT);
        console2.log("paid to members (USDT)", membership.totalPoolPaid() / UNIT);
        console2.log("gross treasury (USDT)", totalTreasury / UNIT);

        // Rotation is admin-only and payout destinations remain distinct. The
        // full accumulated treasury then splits exactly 50/50 to the new pair.
        vm.startPrank(ADMIN);
        membership.setTreasury(NEW_TREASURY);
        membership.setCompanyWallet(NEW_COMPANY);
        membership.withdrawTreasury(totalTreasury);
        vm.stopPrank();

        uint256 expectedCompany = totalTreasury / 2;
        console2.log("treasury wallet share (USDT)", (totalTreasury - expectedCompany) / UNIT);
        console2.log("company wallet share (USDT)", expectedCompany / UNIT);
        assertEq(usdt.balanceOf(NEW_COMPANY), expectedCompany, "wrong company profit");
        assertEq(usdt.balanceOf(NEW_TREASURY), totalTreasury - expectedCompany, "wrong treasury profit");
        assertEq(membership.pendingTreasury(), 0, "treasury remains pending");
        assertEq(usdt.balanceOf(address(membership)), 0, "contract retains USDT");
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
