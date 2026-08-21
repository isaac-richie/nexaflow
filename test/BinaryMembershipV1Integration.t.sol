// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BinaryMembershipV1IntegrationTest is Test {
    BinaryMembershipV1 public membership;
    MockERC20 public token;

    address admin = address(0xAD);
    address treasuryAddr = address(0x7777);
    address operator = address(0x8888);
    address pauser = address(0x9999);

    uint256 constant FEE_1 = 20 ether;
    uint256 constant FEE_2 = 60 ether;
    uint256 constant FEE_3 = 180 ether;
    uint256 constant NODE_1 = 5 ether;
    uint256 constant NODE_2 = 10 ether;
    uint256 constant NODE_3 = 25 ether;

    uint256 constant INITIAL_FUNDING = 10_000_000 ether;

    address root = address(0x1);
    address[] users;

    function setUp() public {
        token = new MockERC20("FAKEUSD", "FUSD", 18);

        vm.startPrank(admin);
        membership = new BinaryMembershipV1(
            IERC20(address(token)), treasuryAddr, admin, 0, root
        );
        membership.grantRole(membership.OPERATOR_ROLE(), operator);
        membership.grantRole(membership.TREASURY_ROLE(), treasuryAddr);
        membership.grantRole(membership.PAUSER_ROLE(), pauser);

        membership.configureStages(
            [uint256(FEE_1), FEE_2, FEE_3, 540 ether, 1620 ether, 4860 ether],
            [uint256(NODE_1), NODE_2, NODE_3, 80 ether, 250 ether, 800 ether],
            [uint256(6), 14, 14, 14, 14, 14],
            [uint256(2), 3, 3, 3, 3, 3],
            [uint256(0), 10, 10, 10, 10, 8]
        );
        vm.stopPrank();

        // Create enough wallets for the 10-rollover ($60 stage) award test.
        for (uint256 i = 0; i < 160; i++) {
            address user = address(uint160(0x1000 + i));
            users.push(user);
            token.mint(user, 100_000 ether);
            vm.prank(user);
            token.approve(address(membership), type(uint256).max);
        }

        // Fund root and contract
        token.mint(root, 100_000 ether);
        vm.prank(root);
        token.approve(address(membership), type(uint256).max);
        token.mint(address(membership), INITIAL_FUNDING);

        // Register root
        vm.prank(root);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);
    }

    // ── Test 1: Full stage-0 tree (7 members total) ──────────────────

    function test_Stage1_Full7MemberTree() public {
        _registerUnderRoot(0, 6);

        (,, uint256 slots, uint256 rollovers,,) = membership.getTreeInfo(root, 0);
        assertEq(slots, 0, "slots should reset after rollover");
        assertEq(rollovers, 1, "root should have rolled over once");

        assertEq(membership.memberCount(), 7, "should be 7 members total");
    }

    // ── Test 2: Multiple rollovers ───────────────────────────────────

    function test_Stage1_MultipleRollovers() public {
        // 18 members = 3 complete trees
        _registerUnderRoot(0, 18);

        (,, uint256 slots, uint256 rollovers,,) = membership.getTreeInfo(root, 0);
        assertEq(rollovers, 3, "should have 3 rollovers");
        assertEq(slots, 0, "slots should be 0 after 3 full cycles");
    }

    // ── Test 3: Stage 2 full tree ────────────────────────────────────

    function test_Stage2_Full15MemberTree() public {
        // First register 14 users in stage 0 (so they're eligible)
        _registerUnderRoot(0, 14);

        // Enroll root at stage 1
        vm.prank(operator);
        membership.enrollStageRoot(root, 1);

        // 14 members join stage 1 under root
        for (uint256 i = 0; i < 14; i++) {
            (address parent, BinaryMembershipV1.Side side) = membership.findOpenSlot(root, 1);
            vm.prank(users[i]);
            membership.joinStage(1, parent, side);
        }

        (,, uint256 slots, uint256 rollovers,,) = membership.getTreeInfo(root, 1);
        assertEq(rollovers, 1, "stage 1 should have rolled over");
        assertEq(slots, 0, "slots reset after rollover");
    }

    // ── Test 4: Three stages with 50 members ─────────────────────────

    function test_ThreeStages_50Members() public {
        // Register 50 members at stage 0
        _registerUnderRoot(0, 50);

        assertEq(membership.memberCount(), 51, "should be 51 total (root + 50)");

        // Verify root's stage-0 rollovers
        (,,, uint256 rollovers0,,) = membership.getTreeInfo(root, 0);
        assertEq(rollovers0, uint256(8), "root stage-0 rollovers = 50/6 = 8");

        // Enroll root at stage 1 and stage 2
        vm.prank(operator);
        membership.enrollStageRoot(root, 1);
        vm.prank(operator);
        membership.enrollStageRoot(root, 2);

        // First 14 users join stage 1
        for (uint256 i = 0; i < 14; i++) {
            (address parent, BinaryMembershipV1.Side side) = membership.findOpenSlot(root, 1);
            vm.prank(users[i]);
            membership.joinStage(1, parent, side);
        }

        // Verify stage 1 rollover
        (,,, uint256 rollovers1,,) = membership.getTreeInfo(root, 1);
        assertEq(rollovers1, 1, "root should have 1 stage-1 rollover");

        // First 14 stage-1 members join stage 2
        for (uint256 i = 0; i < 14; i++) {
            (address parent, BinaryMembershipV1.Side side) = membership.findOpenSlot(root, 2);
            vm.prank(users[i]);
            membership.joinStage(2, parent, side);
        }

        (,,, uint256 rollovers2,,) = membership.getTreeInfo(root, 2);
        assertEq(rollovers2, 1, "root should have 1 stage-2 rollover");

        // Verify total fee accounting
        uint256 expectedTotalFees = 50 * FEE_1 + 14 * FEE_2 + 14 * FEE_3;
        uint256 expectedPoolPaid = 50 * NODE_1 + 14 * NODE_2 + 14 * NODE_3;
        uint256 expectedTreasuryAccum = expectedTotalFees - expectedPoolPaid;

        assertEq(
            membership.totalPoolPaid() + membership.totalTreasuryPaid(),
            expectedTotalFees,
            "total fees don't match"
        );
    }

    // ── Test 5: 100 wallets all register ─────────────────────────────

    function test_100Wallets_AllRegister() public {
        _registerUnderRoot(0, 99); // users[0..98] (root already registered, 99 more = 100 total)

        // Add the last user
        (address parent, BinaryMembershipV1.Side side) = membership.findOpenSlot(root, 0);
        expectedPoolPaid += _expectedPayout(parent, 0);
        vm.prank(users[99]);
        membership.register(root, parent, side);

        assertEq(membership.memberCount(), 101, "should be 101 members (root + 100)");

        uint256 totalFees = 100 * FEE_1;
        assertEq(
            membership.totalPoolPaid() + membership.totalTreasuryPaid(),
            totalFees,
            "fee conservation after 100 joins"
        );

        // Every upline on a board is paid, so the treasury share is whatever
        // the uplines did not consume. Computed by walking the tree, not read
        // back from the contract.
        assertEq(membership.totalPoolPaid(), expectedPoolPaid, "pool paid mismatch");
        assertEq(
            membership.pendingTreasury(),
            totalFees - expectedPoolPaid,
            "pendingTreasury mismatch"
        );
    }

    // ── Test 6: Spillover chain with deep tree ───────────────────────

    function test_SpilloverChain_DeepTree() public {
        // All 30 sponsored by root, placed via BFS
        for (uint256 i = 0; i < 30; i++) {
            (address parent, BinaryMembershipV1.Side side) = membership.findOpenSlot(root, 0);
            require(parent != address(0), "no open slot found");

            vm.prank(users[i]);
            membership.register(root, parent, side);
        }

        assertEq(membership.memberCount(), 31);

        // Root should have rolled over 5 times (30 / 6 = 5)
        (,,, uint256 rollovers,,) = membership.getTreeInfo(root, 0);
        assertEq(rollovers, 5, "root rollovers = 30/6 = 5");

        // Verify all sponsor counts
        assertEq(membership.getCurrentWeekSponsorCount(root), 30);
    }

    // ── Test 7: Cross-stage sponsor follow ───────────────────────────

    function test_CrossStage_SponsorFollow() public {
        // Register 20 users in stage 0
        _registerUnderRoot(0, 20);

        // Enroll root at stage 1
        vm.prank(operator);
        membership.enrollStageRoot(root, 1);

        // users[0] joins stage 1 under root
        vm.prank(users[0]);
        membership.joinStage(1, root, BinaryMembershipV1.Side.Left);

        // users[1] joins stage 1, also under root (different side)
        vm.prank(users[1]);
        membership.joinStage(1, root, BinaryMembershipV1.Side.Right);

        // Verify stage 1 tree structure
        (address left, address right,,,,) = membership.getTreeInfo(root, 1);
        assertEq(left, users[0], "root's left child at stage 1");
        assertEq(right, users[1], "root's right child at stage 1");

        // users[2] joins stage 1 under users[0]
        vm.prank(users[2]);
        membership.joinStage(1, users[0], BinaryMembershipV1.Side.Left);

        (address u0Left,,,,, uint256 u0Earnings) = membership.getTreeInfo(users[0], 1);
        assertEq(u0Left, users[2], "users[0]'s left child at stage 1");
        assertEq(u0Earnings, NODE_2, "users[0] earned node reward from users[2]");
    }

    // ── Test 8: Treasury accounting with 100 members ─────────────────

    function test_TreasuryAccounting_100Members() public {
        _registerUnderRoot(0, 100);

        uint256 expectedPending = (100 * FEE_1) - expectedPoolPaid;
        assertEq(membership.pendingTreasury(), expectedPending, "pending treasury mismatch");

        // Withdraw full pending
        uint256 treasuryBalBefore = token.balanceOf(treasuryAddr);
        vm.prank(treasuryAddr);
        membership.withdrawTreasury(expectedPending);

        assertEq(
            token.balanceOf(treasuryAddr) - treasuryBalBefore,
            expectedPending,
            "treasury balance after withdraw"
        );
        assertEq(membership.pendingTreasury(), 0, "pending should be 0 after full withdraw");

        // Contract should still be solvent
        assertGe(
            token.balanceOf(address(membership)),
            0,
            "contract should not be negative"
        );
    }

    // ── Test 9: Physical award after rollovers ───────────────────────

    function test_PhysicalAward_AfterRollovers() public {
        // Stage 1 needs 10 rollovers × 14 slots = 140 members.
        _registerUnderRoot(0, 150);

        // Enroll root at stage 1
        vm.prank(operator);
        membership.enrollStageRoot(root, 1);

        // 140 members join stage 1.
        for (uint256 i = 0; i < 140; i++) {
            (address parent, BinaryMembershipV1.Side side) = membership.findOpenSlot(root, 1);
            vm.prank(users[i]);
            membership.joinStage(1, parent, side);
        }

        // Root should have 10 rollovers at stage 1.
        (,,, uint256 rollovers,,) = membership.getTreeInfo(root, 1);
        assertEq(rollovers, 10, "root needs 10 rollovers for award");

        // The award is capped at a share of what root actually earned here,
        // which is what makes self-farming the threshold unprofitable.
        (,,,,, uint256 rootStage1Earnings) = membership.getTreeInfo(root, 1);
        uint256 awardAmount =
            (rootStage1Earnings * membership.awardCapBps()) / 10_000;

        // Anything above the cap is refused
        vm.expectRevert(
            abi.encodeWithSelector(
                BinaryMembershipV1.AwardExceedsCap.selector,
                awardAmount,
                awardAmount + 1
            )
        );
        vm.prank(operator);
        membership.grantPhysicalAward(root, 1, awardAmount + 1);

        uint256 rootBalBefore = token.balanceOf(root);

        vm.prank(operator);
        membership.grantPhysicalAward(root, 1, awardAmount);

        assertEq(
            token.balanceOf(root) - rootBalBefore,
            awardAmount,
            "award not received"
        );

        (,,,, uint256 lastAwarded,) = membership.getTreeInfo(root, 1);
        assertGt(lastAwarded, 0, "lastAwardedRollover should be set");

        assertEq(membership.getAwardRecordCount(), 1, "should have 1 award record");

        // Immediate re-claim reverts — another 10 rollovers are required.
        (,,, uint256 currentRoll,,) = membership.getTreeInfo(root, 1);
        uint256 nextMilestone = lastAwarded + 10;
        vm.expectRevert(
            abi.encodeWithSelector(
                BinaryMembershipV1.RolloversNotMet.selector, nextMilestone, currentRoll
            )
        );
        vm.prank(operator);
        membership.grantPhysicalAward(root, 1, 1);
    }

    // ── Test 10: Pause blocks all joins ──────────────────────────────

    function test_Pause_BlocksAllJoins() public {
        _registerUnderRoot(0, 5);

        vm.prank(pauser);
        membership.pause();

        // Register should revert
        vm.expectRevert();
        vm.prank(users[5]);
        membership.register(root, root, BinaryMembershipV1.Side.Left);

        // joinStage should revert
        vm.prank(operator);
        membership.enrollStageRoot(root, 1);

        vm.expectRevert();
        vm.prank(users[0]);
        membership.joinStage(1, root, BinaryMembershipV1.Side.Left);

        // Unpause
        vm.prank(pauser);
        membership.unpause();

        // Should work now
        (address parent, BinaryMembershipV1.Side side) = membership.findOpenSlot(root, 0);
        vm.prank(users[5]);
        membership.register(root, parent, side);

        assertEq(membership.memberCount(), 7);
    }

    // ── Helpers ──────────────────────────────────────────────────────

    /// @dev Accumulated independently of the contract: walks the tree to count
    ///      how many uplines each placement should pay, rather than trusting
    ///      the payment code to report its own total.
    uint256 public expectedPoolPaid;

    function _expectedPayout(address parent, uint256 stageId)
        internal
        view
        returns (uint256)
    {
        BinaryMembershipV1.StageConfig memory c = membership.getStageConfig(stageId);
        uint256 count;
        address cur = parent;
        while (cur != address(0) && count < c.treeDepth) {
            count++;
            cur = membership.getStageMembership(cur, stageId).parent;
        }
        return count * c.nodeReward;
    }

    function _registerUnderRoot(uint256 startIdx, uint256 count) internal {
        for (uint256 i = 0; i < count; i++) {
            (address parent, BinaryMembershipV1.Side side) = membership.findOpenSlot(root, 0);
            expectedPoolPaid += _expectedPayout(parent, 0);
            vm.prank(users[startIdx + i]);
            membership.register(root, parent, side);
        }
    }

    function _assertGlobalAccounting() internal view {
        uint256 contractBal = token.balanceOf(address(membership));
        assertGe(contractBal, membership.pendingTreasury(), "insolvent");

        assertEq(
            membership.totalPoolPaid() + membership.totalTreasuryPaid(),
            (membership.memberCount() - 1) * FEE_1,
            "fee conservation (stage 0 only)"
        );
    }
}
