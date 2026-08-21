// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BinaryMembershipV1VisualTest is Test {
    BinaryMembershipV1 public membership;
    MockERC20 public token;

    address admin = address(0xAD);
    address treasuryWallet = address(0x7EA5);
    address operator = address(0x8888);
    address pauser = address(0x9999);

    uint256 constant FEE_0 = 20 ether;
    uint256 constant FEE_1 = 60 ether;
    uint256 constant FEE_2 = 180 ether;
    uint256 constant NODE_0 = 5 ether;
    uint256 constant NODE_1 = 10 ether;
    uint256 constant NODE_2 = 25 ether;

    address root = address(0x1);
    address[] users;

    function setUp() public {
        token = new MockERC20("FAKEUSD", "FUSD", 18);

        vm.startPrank(admin);
        membership = new BinaryMembershipV1(
            IERC20(address(token)), treasuryWallet, admin, 0, root
        );
        membership.grantRole(membership.OPERATOR_ROLE(), operator);
        membership.grantRole(membership.TREASURY_ROLE(), treasuryWallet);
        membership.grantRole(membership.PAUSER_ROLE(), pauser);

        membership.configureStages(
            [uint256(FEE_0), FEE_1, FEE_2, 540 ether, 1620 ether, 4860 ether],
            [uint256(NODE_0), NODE_1, NODE_2, 80 ether, 250 ether, 800 ether],
            [uint256(6), 14, 14, 14, 14, 14],
            [uint256(2), 3, 3, 3, 3, 3],
            [uint256(0), 10, 10, 10, 10, 8]
        );
        vm.stopPrank();

        // Create 100 wallets
        for (uint256 i = 0; i < 100; i++) {
            address user = address(uint160(0x1000 + i));
            users.push(user);
            token.mint(user, 500_000 ether);
            vm.prank(user);
            token.approve(address(membership), type(uint256).max);
        }

        // Fund root
        token.mint(root, 500_000 ether);
        vm.prank(root);
        token.approve(address(membership), type(uint256).max);

        // Fund contract for award payouts
        token.mint(address(membership), 5_000_000 ether);
    }

    function test_Visual_100Wallets_3Stages() public {
        console.log("============================================================");
        console.log("  BINARY MEMBERSHIP V1 -- 100 WALLET STRESS TEST");
        console.log("  3 Stages | Spillover | Rollover | Treasury");
        console.log("============================================================");
        console.log("");

        // ─── PHASE 1: ROOT REGISTRATION ──────────────────────────────
        console.log("--- PHASE 1: ROOT REGISTRATION ---");
        vm.prank(root);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);
        console.log("Root registered:", root);
        console.log("Member count:", membership.memberCount());
        console.log("");

        // ─── PHASE 2: REGISTER 100 WALLETS AT STAGE 0 ───────────────
        console.log("--- PHASE 2: REGISTER 100 WALLETS (STAGE 0 -- $20 fee) ---");
        console.log("Fee: $20 | Node reward: $5 to parent | Treasury: $15");
        console.log("Tree: 6 slots (2 levels) | Rollover every 6 members");
        console.log("");

        uint256 lastRollover = 0;

        for (uint256 i = 0; i < 100; i++) {
            // Find open slot via BFS (spillover)
            (address parent, BinaryMembershipV1.Side side) =
                membership.findOpenSlot(root, 0);

            uint256 parentBalBefore = token.balanceOf(parent);

            vm.prank(users[i]);
            membership.register(root, parent, side);

            uint256 parentReward = token.balanceOf(parent) - parentBalBefore;

            // Check for rollover
            (,, uint256 slots, uint256 rollovers,,) = membership.getTreeInfo(root, 0);

            string memory sideStr = side == BinaryMembershipV1.Side.Left ? "L" : "R";

            // Log every 6th member (rollover boundary) and first few
            if (i < 6 || rollovers > lastRollover || i == 99) {
                console.log("----");
                console.log("  Member #%d placed under %s [%s]", i + 1, parent, sideStr);
                console.log("  Parent earned: %d FUSD", parentReward / 1 ether);
                console.log("  Root slots filled: %d | Rollovers: %d", slots, rollovers);

                if (rollovers > lastRollover) {
                    console.log("  >>> ROLLOVER #%d! Tree reset, fresh cycle <<<", rollovers);
                    lastRollover = rollovers;
                }
            }
        }

        console.log("");
        console.log("--- STAGE 0 RESULTS ---");
        console.log("Members registered: %d", membership.memberCount());
        (,, uint256 rootSlots, uint256 rootRollovers,,) = membership.getTreeInfo(root, 0);
        console.log("Root rollovers: %d (100/6 = 16 full + 4 remaining)", rootRollovers);
        console.log("Root slots in current cycle: %d", rootSlots);
        console.log("");

        _logAccounting("AFTER STAGE 0");

        // ─── PHASE 3: TREASURY WITHDRAWAL ────────────────────────────
        console.log("");
        console.log("--- PHASE 3: TREASURY WITHDRAWAL ---");
        uint256 pendingBefore = membership.pendingTreasury();
        uint256 treasuryBalBefore = token.balanceOf(treasuryWallet);
        console.log("Pending treasury: %d FUSD", pendingBefore / 1 ether);
        console.log("Treasury wallet balance before: %d FUSD", treasuryBalBefore / 1 ether);

        // Withdraw half
        uint256 halfWithdraw = pendingBefore / 2;
        vm.prank(treasuryWallet);
        membership.withdrawTreasury(halfWithdraw);

        console.log("Withdrew: %d FUSD", halfWithdraw / 1 ether);
        console.log("Treasury wallet balance after: %d FUSD", token.balanceOf(treasuryWallet) / 1 ether);
        console.log("Remaining pending: %d FUSD", membership.pendingTreasury() / 1 ether);
        console.log("");

        // ─── PHASE 4: ENROLL ROOT AT STAGE 1 & STAGE 2 ──────────────
        console.log("--- PHASE 4: STAGE PROGRESSION ---");
        vm.prank(operator);
        membership.enrollStageRoot(root, 1);
        console.log("Root enrolled at STAGE 1 (fee: $60, node reward: $10)");

        vm.prank(operator);
        membership.enrollStageRoot(root, 2);
        console.log("Root enrolled at STAGE 2 (fee: $180, node reward: $25)");
        console.log("");

        // ─── PHASE 5: 42 MEMBERS JOIN STAGE 1 ───────────────────────
        console.log("--- PHASE 5: 42 MEMBERS JOIN STAGE 1 ($60 fee) ---");
        console.log("Tree: 14 slots (3 levels) | Rollover every 14 members");
        console.log("Expected: 3 full rollovers (42/14 = 3)");
        console.log("");

        uint256 stage1Rollovers = 0;
        for (uint256 i = 0; i < 42; i++) {
            (address parent, BinaryMembershipV1.Side side) =
                membership.findOpenSlot(root, 1);

            uint256 parentBalBefore2 = token.balanceOf(parent);

            vm.prank(users[i]);
            membership.joinStage(1, parent, side);

            uint256 parentReward2 = token.balanceOf(parent) - parentBalBefore2;

            (,, uint256 s1Slots, uint256 s1Rolls,,) = membership.getTreeInfo(root, 1);

            string memory sideStr2 = side == BinaryMembershipV1.Side.Left ? "L" : "R";

            // Log first tree fill, each rollover, and key moments
            if (i < 2 || s1Rolls > stage1Rollovers || i == 41) {
                console.log("  Stage1 member #%d under %s [%s]", i + 1, parent, sideStr2);
                console.log("    Parent earned: %d FUSD | Root slots: %d | Rollovers: %d",
                    parentReward2 / 1 ether, s1Slots, s1Rolls);

                if (s1Rolls > stage1Rollovers) {
                    console.log("    >>> STAGE 1 ROLLOVER #%d <<<", s1Rolls);
                    stage1Rollovers = s1Rolls;
                }
            }
        }

        console.log("");
        (,,, uint256 rootS1Rolls,,) = membership.getTreeInfo(root, 1);
        console.log("Root stage 1 rollovers: %d", rootS1Rolls);

        _logAccounting("AFTER STAGE 1");

        // ─── PHASE 6: 28 MEMBERS JOIN STAGE 2 ───────────────────────
        console.log("");
        console.log("--- PHASE 6: 28 MEMBERS JOIN STAGE 2 ($180 fee) ---");
        console.log("Expected: 2 full rollovers (28/14 = 2)");
        console.log("");

        uint256 stage2Rollovers = 0;
        for (uint256 i = 0; i < 28; i++) {
            (address parent, BinaryMembershipV1.Side side) =
                membership.findOpenSlot(root, 2);

            uint256 parentBalBefore3 = token.balanceOf(parent);

            vm.prank(users[i]);
            membership.joinStage(2, parent, side);

            uint256 parentReward3 = token.balanceOf(parent) - parentBalBefore3;
            (,, uint256 s2Slots, uint256 s2Rolls,,) = membership.getTreeInfo(root, 2);

            string memory sideStr3 = side == BinaryMembershipV1.Side.Left ? "L" : "R";

            if (i < 2 || s2Rolls > stage2Rollovers || i == 27) {
                console.log("  Stage2 member #%d under %s [%s]", i + 1, parent, sideStr3);
                console.log("    Parent earned: %d FUSD | Root slots: %d | Rollovers: %d",
                    parentReward3 / 1 ether, s2Slots, s2Rolls);

                if (s2Rolls > stage2Rollovers) {
                    console.log("    >>> STAGE 2 ROLLOVER #%d <<<", s2Rolls);
                    stage2Rollovers = s2Rolls;
                }
            }
        }

        console.log("");
        (,,, uint256 rootS2Rolls,,) = membership.getTreeInfo(root, 2);
        console.log("Root stage 2 rollovers: %d", rootS2Rolls);

        _logAccounting("AFTER STAGE 2");

        // ─── PHASE 7: SPILLOVER VERIFICATION ─────────────────────────
        console.log("");
        console.log("--- PHASE 7: SPILLOVER TREE STRUCTURE ---");
        console.log("Checking stage 0 tree after 100 members (16 rollovers + 4 remaining):");

        (address rLeft, address rRight, uint256 rSlots, uint256 rRolls,,) =
            membership.getTreeInfo(root, 0);
        console.log("  Root -> Left: %s | Right: %s", rLeft, rRight);
        console.log("  Root slots: %d | Rollovers: %d", rSlots, rRolls);

        if (rLeft != address(0)) {
            (address l2Left, address l2Right,,,,) = membership.getTreeInfo(rLeft, 0);
            console.log("  Root.Left -> L: %s | R: %s", l2Left, l2Right);
        }
        if (rRight != address(0)) {
            (address r2Left, address r2Right,,,,) = membership.getTreeInfo(rRight, 0);
            console.log("  Root.Right -> L: %s | R: %s", r2Left, r2Right);
        }

        // ─── PHASE 8: MEMBER EARNINGS REPORT ─────────────────────────
        console.log("");
        console.log("--- PHASE 8: TOP EARNER REPORT ---");

        // Root earnings
        BinaryMembershipV1.Member memory rootMem = membership.getMember(root);
        console.log("ROOT total earned: %d FUSD", rootMem.totalEarned / 1 ether);

        (,,,,, uint256 rootS0Earn) = membership.getTreeInfo(root, 0);
        (,,,,, uint256 rootS1Earn) = membership.getTreeInfo(root, 1);
        (,,,,, uint256 rootS2Earn) = membership.getTreeInfo(root, 2);
        console.log("  Stage 0 earnings: %d FUSD", rootS0Earn / 1 ether);
        console.log("  Stage 1 earnings: %d FUSD", rootS1Earn / 1 ether);
        console.log("  Stage 2 earnings: %d FUSD", rootS2Earn / 1 ether);

        // Top 5 earners from users
        console.log("");
        console.log("Top earners from 100 members:");
        uint256[5] memory topEarnings;
        uint256[5] memory topIdx;
        for (uint256 i = 0; i < 100; i++) {
            BinaryMembershipV1.Member memory m = membership.getMember(users[i]);
            uint256 earned = m.totalEarned;
            for (uint256 j = 0; j < 5; j++) {
                if (earned > topEarnings[j]) {
                    // Shift down
                    for (uint256 k = 4; k > j; k--) {
                        topEarnings[k] = topEarnings[k - 1];
                        topIdx[k] = topIdx[k - 1];
                    }
                    topEarnings[j] = earned;
                    topIdx[j] = i;
                    break;
                }
            }
        }
        for (uint256 j = 0; j < 5; j++) {
            if (topEarnings[j] > 0) {
                console.log("  #%d User[%d] earned: %d FUSD",
                    j + 1, topIdx[j], topEarnings[j] / 1 ether);
            }
        }

        // ─── PHASE 9: PHYSICAL AWARD ─────────────────────────────────
        console.log("");
        console.log("--- PHASE 9: PHYSICAL AWARD CHECK ---");

        // The $60 stage now needs 10 rollovers. This walkthrough deliberately
        // reaches the old five-rollover boundary and proves it no longer pays.
        (,,, uint256 s1RollCheck,,) = membership.getTreeInfo(root, 1);
        uint256 awardThreshold = membership.getStageConfig(1).rolloversForAward;
        console.log("Root stage 1 rollovers: %d (need %d for award)",
            s1RollCheck, awardThreshold);

        // Keep the original 70-member walkthrough: 42 already joined, so 28
        // more produce exactly five rollovers.
        uint256 moreNeeded = (5 * 14) - 42;
        for (uint256 i = 42; i < 42 + moreNeeded; i++) {
            (address parent, BinaryMembershipV1.Side side) =
                membership.findOpenSlot(root, 1);
            vm.prank(users[i]);
            membership.joinStage(1, parent, side);
        }

        (,,, uint256 s1Final,,) = membership.getTreeInfo(root, 1);
        console.log("Root stage 1 rollovers now: %d - still below new threshold", s1Final);
        assertEq(s1Final, 5, "walkthrough should stop at old threshold");
        vm.expectRevert(
            abi.encodeWithSelector(
                BinaryMembershipV1.RolloversNotMet.selector, awardThreshold, s1Final
            )
        );
        vm.prank(operator);
        membership.grantPhysicalAward(root, 1, 1 ether);

        // ─── PHASE 10: FINAL TREASURY DRAIN ──────────────────────────
        console.log("");
        console.log("--- PHASE 10: FINAL TREASURY ---");
        uint256 finalPending = membership.pendingTreasury();
        console.log("Final pending treasury: %d FUSD", finalPending / 1 ether);

        uint256 tBalBefore = token.balanceOf(treasuryWallet);
        vm.prank(treasuryWallet);
        membership.withdrawTreasury(finalPending);
        uint256 tBalAfter = token.balanceOf(treasuryWallet);

        console.log("Treasury wallet received: %d FUSD", (tBalAfter - tBalBefore) / 1 ether);
        console.log("Treasury wallet total balance: %d FUSD", tBalAfter / 1 ether);
        console.log("Remaining pending: %d FUSD", membership.pendingTreasury() / 1 ether);

        // ─── PHASE 11: FINAL ACCOUNTING ──────────────────────────────
        console.log("");
        _logAccounting("FINAL");

        // ─── PHASE 12: WEEKLY SPONSOR ────────────────────────────────
        console.log("");
        console.log("--- WEEKLY SPONSOR LEADERBOARD ---");
        console.log("Root sponsored all 100 members this week");
        console.log("Root weekly count: %d", membership.getCurrentWeekSponsorCount(root));

        // ─── ASSERTIONS ──────────────────────────────────────────────
        console.log("");
        console.log("============================================================");
        console.log("  ASSERTIONS");
        console.log("============================================================");

        assertEq(membership.memberCount(), 101, "member count");
        assertEq(membership.pendingTreasury(), 0, "pending treasury drained");
        assertGe(
            token.balanceOf(address(membership)),
            0,
            "contract not negative"
        );

        // Fee conservation across all stages
        // Stage 0: 100 members × $20 = $2000
        // Stage 1: 70 members × $60 = $4200
        // Stage 2: 28 members × $180 = $5040
        uint256 totalFeesExpected = (100 * FEE_0) + (70 * FEE_1) + (28 * FEE_2);
        assertEq(
            membership.totalPoolPaid() + membership.totalTreasuryPaid(),
            totalFeesExpected,
            "fee conservation"
        );

        console.log("All assertions passed!");
        console.log("Total fees processed: %d FUSD", totalFeesExpected / 1 ether);
        console.log("Contract balance: %d FUSD", token.balanceOf(address(membership)) / 1 ether);
        console.log("============================================================");
    }

    function _logAccounting(string memory label) internal view {
        console.log("=== ACCOUNTING: %s ===", label);
        console.log("  Total pool paid (node rewards): %d FUSD", membership.totalPoolPaid() / 1 ether);
        console.log("  Total treasury accumulated: %d FUSD", membership.totalTreasuryPaid() / 1 ether);
        console.log("  Pending treasury: %d FUSD", membership.pendingTreasury() / 1 ether);
        console.log("  Contract balance: %d FUSD", token.balanceOf(address(membership)) / 1 ether);
        console.log("  Treasury wallet balance: %d FUSD", token.balanceOf(treasuryWallet) / 1 ether);
        console.log("  Total fees (pool+treasury): %d FUSD",
            (membership.totalPoolPaid() + membership.totalTreasuryPaid()) / 1 ether);
    }
}
