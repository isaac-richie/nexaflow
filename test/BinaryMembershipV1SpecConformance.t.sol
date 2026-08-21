// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Conformance tests written against the HANDWRITTEN COMPENSATION PLAN,
///         not against the contract's behaviour.
///
///  The plan marks every position on a board with the node amount:
///    Stage 0 board — 6 positions x $5  => board owner collects $30
///    Stage 1 board — 14 positions x $10 => board owner collects $140
///
///  Those totals are only reachable if EVERY upline whose board the placement
///  lands on is paid, not just the direct parent. Direct-parent-only pays the
///  board owner $10 and $20 — 3x and 7x short.
///
///  These numbers are hardcoded from the plan. If the contract ever drifts back
///  to direct-parent-only, these fail. That is the whole point of the file.
contract BinaryMembershipV1SpecConformanceTest is Test {
    BinaryMembershipV1 public membership;
    MockERC20 public token;

    address admin = address(0xAD);
    address treasuryWallet = address(0x7EA5);
    address operator = address(0x0B);

    address root = address(0x1);
    address[] public users;

    // ── Straight from the plan ───────────────────────────────────────
    uint256 constant STAGE0_FEE = 20 ether;
    uint256 constant STAGE0_NODE = 5 ether;
    uint256 constant STAGE0_POSITIONS = 6;
    uint256 constant STAGE0_OWNER_COLLECTS = 30 ether; // 6 x $5

    uint256 constant STAGE1_FEE = 60 ether;
    uint256 constant STAGE1_NODE = 10 ether;
    uint256 constant STAGE1_POSITIONS = 14;
    uint256 constant STAGE1_OWNER_COLLECTS = 140 ether; // 14 x $10

    function setUp() public {
        token = new MockERC20("FAKEUSD", "FUSD", 0);

        vm.startPrank(admin);
        membership = new BinaryMembershipV1(
            IERC20(address(token)), treasuryWallet, admin, 0, root
        );
        membership.grantRole(membership.OPERATOR_ROLE(), operator);
        membership.grantRole(membership.TREASURY_ROLE(), treasuryWallet);

        membership.configureStages(
            [STAGE0_FEE, STAGE1_FEE, 180 ether, 540 ether, 1620 ether, 4860 ether],
            [STAGE0_NODE, STAGE1_NODE, 25 ether, 80 ether, 250 ether, 800 ether],
            [STAGE0_POSITIONS, STAGE1_POSITIONS, 14, 14, 14, 14],
            [uint256(2), 3, 3, 3, 3, 3],
            [uint256(0), 10, 10, 10, 10, 8]
        );
        vm.stopPrank();

        for (uint256 i = 0; i < 40; i++) {
            address u = address(uint160(0x400000 + i));
            users.push(u);
            token.mint(u, 100_000 ether);
            vm.prank(u);
            token.approve(address(membership), type(uint256).max);
        }

        token.mint(address(membership), 1_000_000 ether);

        vm.prank(root);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);
    }

    // ══════════════════════════════════════════════════════════════════
    //  THE HEADLINE NUMBERS FROM THE PLAN
    // ══════════════════════════════════════════════════════════════════

    /// @notice Plan: a full stage-0 board pays its owner $5 x 6 = $30.
    function test_Spec_Stage0_BoardOwnerCollects30() public {
        uint256 before = token.balanceOf(root);

        for (uint256 i = 0; i < STAGE0_POSITIONS; i++) {
            (address p, BinaryMembershipV1.Side s) = membership.findOpenSlot(root, 0);
            vm.prank(users[i]);
            membership.register(root, p, s);
        }

        uint256 collected = token.balanceOf(root) - before;

        console.log("  stage 0 board owner collected: %d FUSD", collected / 1 ether);
        console.log("  plan says:                     30 FUSD");

        assertEq(
            collected,
            STAGE0_OWNER_COLLECTS,
            "PLAN VIOLATION: stage-0 board owner did not collect 6 x nodeReward"
        );
    }

    /// @notice Plan: a full stage-1 board pays its owner $10 x 14 = $140.
    function test_Spec_Stage1_BoardOwnerCollects140() public {
        // Everyone needs stage 0 first
        for (uint256 i = 0; i < STAGE1_POSITIONS; i++) {
            (address p, BinaryMembershipV1.Side s) = membership.findOpenSlot(root, 0);
            vm.prank(users[i]);
            membership.register(root, p, s);
        }

        vm.prank(operator);
        membership.enrollStageRoot(root, 1);

        uint256 before = token.balanceOf(root);

        for (uint256 i = 0; i < STAGE1_POSITIONS; i++) {
            (address p, BinaryMembershipV1.Side s) = membership.findOpenSlot(root, 1);
            vm.prank(users[i]);
            membership.joinStage(1, p, s);
        }

        uint256 collected = token.balanceOf(root) - before;

        console.log("  stage 1 board owner collected: %d FUSD", collected / 1 ether);
        console.log("  plan says:                     140 FUSD");

        assertEq(
            collected,
            STAGE1_OWNER_COLLECTS,
            "PLAN VIOLATION: stage-1 board owner did not collect 14 x nodeReward"
        );
    }

    // ══════════════════════════════════════════════════════════════════
    //  MID-BOARD MEMBERS MUST EARN TOO
    // ══════════════════════════════════════════════════════════════════

    /// @notice The people between the owner and the bottom are the ones
    ///         direct-parent-only shortchanged worst. On a full stage-1 board
    ///         a level-1 member has 6 descendants, so collects 6 x $10 = $60.
    function test_Spec_Stage1_MidBoardMemberCollects60() public {
        for (uint256 i = 0; i < STAGE1_POSITIONS; i++) {
            (address p, BinaryMembershipV1.Side s) = membership.findOpenSlot(root, 0);
            vm.prank(users[i]);
            membership.register(root, p, s);
        }

        vm.prank(operator);
        membership.enrollStageRoot(root, 1);

        // users[0] takes root's left slot -> level 1 of the board
        vm.prank(users[0]);
        membership.joinStage(1, root, BinaryMembershipV1.Side.Left);

        uint256 before = token.balanceOf(users[0]);

        for (uint256 i = 1; i < STAGE1_POSITIONS; i++) {
            (address p, BinaryMembershipV1.Side s) = membership.findOpenSlot(root, 1);
            vm.prank(users[i]);
            membership.joinStage(1, p, s);
        }

        uint256 collected = token.balanceOf(users[0]) - before;

        console.log("  level-1 member collected: %d FUSD", collected / 1 ether);
        console.log("  expected (6 descendants): 60 FUSD");

        assertEq(
            collected,
            6 * STAGE1_NODE,
            "PLAN VIOLATION: mid-board member did not collect from all 6 descendants"
        );
    }

    // ══════════════════════════════════════════════════════════════════
    //  BOARD TOTALS AND SOLVENCY
    // ══════════════════════════════════════════════════════════════════

    /// @notice A full stage-0 board makes 10 payments (1+1+2+2+2+2) = $50,
    ///         funded by 6 x $20 = $120. Treasury keeps $70.
    function test_Spec_Stage0_BoardTotalsAndSolvency() public {
        for (uint256 i = 0; i < STAGE0_POSITIONS; i++) {
            (address p, BinaryMembershipV1.Side s) = membership.findOpenSlot(root, 0);
            vm.prank(users[i]);
            membership.register(root, p, s);
        }

        uint256 revenue = STAGE0_POSITIONS * STAGE0_FEE; // $120
        uint256 paidOut = membership.totalPoolPaid();
        uint256 toTreasury = membership.totalTreasuryPaid();

        console.log("  revenue:  %d FUSD", revenue / 1 ether);
        console.log("  paid out: %d FUSD (plan: 50)", paidOut / 1 ether);
        console.log("  treasury: %d FUSD (plan: 70)", toTreasury / 1 ether);

        assertEq(paidOut, 50 ether, "board payout total wrong");
        assertEq(toTreasury, 70 ether, "treasury share wrong");
        assertEq(paidOut + toTreasury, revenue, "fee conservation broken");

        // Solvent by a wide margin - this is what I previously got wrong
        assertLt(paidOut, revenue / 2, "payout should be under half of revenue");
    }

    /// @notice A full stage-1 board makes 34 payments x $10 = $340 from
    ///         14 x $60 = $840. Treasury keeps $500.
    function test_Spec_Stage1_BoardTotalsAndSolvency() public {
        for (uint256 i = 0; i < STAGE1_POSITIONS; i++) {
            (address p, BinaryMembershipV1.Side s) = membership.findOpenSlot(root, 0);
            vm.prank(users[i]);
            membership.register(root, p, s);
        }

        vm.prank(operator);
        membership.enrollStageRoot(root, 1);

        uint256 poolBefore = membership.totalPoolPaid();
        uint256 treasuryBefore = membership.totalTreasuryPaid();

        for (uint256 i = 0; i < STAGE1_POSITIONS; i++) {
            (address p, BinaryMembershipV1.Side s) = membership.findOpenSlot(root, 1);
            vm.prank(users[i]);
            membership.joinStage(1, p, s);
        }

        uint256 paidOut = membership.totalPoolPaid() - poolBefore;
        uint256 toTreasury = membership.totalTreasuryPaid() - treasuryBefore;
        uint256 revenue = STAGE1_POSITIONS * STAGE1_FEE;

        console.log("  revenue:  %d FUSD", revenue / 1 ether);
        console.log("  paid out: %d FUSD (plan: 340)", paidOut / 1 ether);
        console.log("  treasury: %d FUSD (plan: 500)", toTreasury / 1 ether);

        assertEq(paidOut, 340 ether, "stage-1 board payout total wrong");
        assertEq(toTreasury, 500 ether, "stage-1 treasury share wrong");
        assertLt(paidOut, revenue / 2, "payout should be under half of revenue");
    }

    // ══════════════════════════════════════════════════════════════════
    //  PAYOUT DEPTH IS CAPPED AT THE BOARD
    // ══════════════════════════════════════════════════════════════════

    /// @notice A member more than treeDepth levels above a placement is NOT on
    ///         its board and must not be paid. Without this cap a deep chain
    ///         would pay unbounded uplines from a fixed fee.
    function test_Spec_PayoutCappedAtBoardDepth() public {
        // Build a manual chain 5 deep at stage 0 (treeDepth = 2)
        address prev = root;
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(users[i]);
            membership.register(root, prev, BinaryMembershipV1.Side.Left);
            prev = users[i];
        }

        // Place one more at the bottom and watch who gets paid
        uint256 rootBefore = token.balanceOf(root);
        uint256 l1Before = token.balanceOf(users[2]); // 3 levels up - off the board
        uint256 l2Before = token.balanceOf(users[3]); // 2 levels up - on the board
        uint256 l3Before = token.balanceOf(users[4]); // direct parent

        vm.prank(users[5]);
        membership.register(root, users[4], BinaryMembershipV1.Side.Left);

        assertEq(
            token.balanceOf(users[4]) - l3Before,
            STAGE0_NODE,
            "direct parent unpaid"
        );
        assertEq(
            token.balanceOf(users[3]) - l2Before,
            STAGE0_NODE,
            "second-level upline unpaid"
        );
        assertEq(
            token.balanceOf(users[2]) - l1Before,
            0,
            "third-level upline paid despite being off the board (treeDepth = 2)"
        );
        assertEq(
            token.balanceOf(root) - rootBefore,
            0,
            "root paid despite being far off the board"
        );

        // Exactly treeDepth payments were made
        assertEq(
            membership.totalPoolPaid(),
            6 * 2 * STAGE0_NODE - STAGE0_NODE,
            "unexpected total payout across the chain"
        );
    }

    // ══════════════════════════════════════════════════════════════════
    //  CONFIG MUST REJECT AN INSOLVENT BOARD
    // ══════════════════════════════════════════════════════════════════

    /// @notice treeDepth x nodeReward must stay under the fee, otherwise a
    ///         full-depth placement would pay out more than it collected.
    function test_Spec_ConfigRejectsInsolventStage() public {
        BinaryMembershipV1 fresh;
        vm.startPrank(admin);
        fresh = new BinaryMembershipV1(
            IERC20(address(token)), treasuryWallet, admin, 0, root
        );

        // depth 3 x $25 = $75 against a $60 fee -> insolvent
        vm.expectRevert(BinaryMembershipV1.InvalidFeeConfig.selector);
        fresh.configureStages(
            [uint256(20 ether), 60 ether, 180 ether, 540 ether, 1620 ether, 4860 ether],
            [uint256(5 ether), 25 ether, 25 ether, 80 ether, 250 ether, 800 ether],
            [uint256(6), 14, 14, 14, 14, 14],
            [uint256(2), 3, 3, 3, 3, 3],
            [uint256(0), 10, 10, 10, 10, 8]
        );
        vm.stopPrank();

        // Same rule on the runtime setter: depth 3 x $20 = $60, not under $60
        vm.expectRevert(BinaryMembershipV1.InvalidFeeConfig.selector);
        vm.prank(admin);
        membership.updateStageFee(1, 60 ether, 20 ether);

        // One wei under is acceptable
        vm.prank(admin);
        membership.updateStageFee(1, 60 ether, 19_999_999_999_999_999_999);
    }
}
