// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BinaryMembershipV1Test is Test {
    BinaryMembershipV1 public membership;
    MockERC20 public token;

    address admin = address(0xAD);
    address treasury = address(0x7777);
    address operator = address(0x8888);
    address pauser = address(0x9999);

    // Stage fees (in token wei, using 18 decimals)
    uint256 constant FEE_1 = 20 ether;
    uint256 constant FEE_2 = 60 ether;
    uint256 constant FEE_3 = 180 ether;
    uint256 constant FEE_4 = 540 ether;
    uint256 constant FEE_5 = 1620 ether;
    uint256 constant FEE_6 = 4860 ether;

    // Node rewards per stage
    uint256 constant NODE_1 = 5 ether;
    uint256 constant NODE_2 = 10 ether;
    uint256 constant NODE_3 = 25 ether;
    uint256 constant NODE_4 = 80 ether;
    uint256 constant NODE_5 = 250 ether;
    uint256 constant NODE_6 = 800 ether;

    address root = address(0x1);
    address[] users;

    function setUp() public {
        token = new MockERC20("RWAAN", "RWAAN", 18);

        vm.startPrank(admin);
        membership = new BinaryMembershipV1(
            IERC20(address(token)),
            treasury,
            admin,
            0, // no admin delay for testing
            root
        );

        membership.grantRole(membership.OPERATOR_ROLE(), operator);
        membership.grantRole(membership.PAUSER_ROLE(), pauser);
        membership.grantRole(membership.TREASURY_ROLE(), treasury);

        uint256[6] memory fees = [FEE_1, FEE_2, FEE_3, FEE_4, FEE_5, FEE_6];
        uint256[6] memory nodeRewards = [NODE_1, NODE_2, NODE_3, NODE_4, NODE_5, NODE_6];
        uint256[6] memory treeSlots = [uint256(6), 14, 14, 14, 14, 14];
        uint256[6] memory treeDepths = [uint256(2), 3, 3, 3, 3, 3];
        uint256[6] memory rolloversForAward = [uint256(0), 10, 10, 10, 10, 8];

        membership.configureStages(fees, nodeRewards, treeSlots, treeDepths, rolloversForAward);
        vm.stopPrank();

        // Create 30 user addresses and fund them
        for (uint256 i = 0; i < 30; i++) {
            address user = address(uint160(0x1000 + i));
            users.push(user);
            token.mint(user, 100_000 ether);
            vm.prank(user);
            token.approve(address(membership), type(uint256).max);
        }

        // Fund root
        token.mint(root, 100_000 ether);
        vm.prank(root);
        token.approve(address(membership), type(uint256).max);

        // Fund contract for reward payouts
        token.mint(address(membership), 1_000_000 ether);
    }

    function test_ClientAwardThresholdSchedule() public view {
        uint256[6] memory expected = [uint256(0), 10, 10, 10, 10, 8];
        for (uint256 stageId; stageId < 6; stageId++) {
            assertEq(
                membership.getStageConfig(stageId).rolloversForAward,
                expected[stageId],
                "award rollover schedule drift"
            );
        }
    }

    // ────────────────────────────────────────────────────────────────
    //  Registration
    // ────────────────────────────────────────────────────────────────

    function test_RootRegistration() public {
        vm.prank(root);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);

        assertEq(membership.memberCount(), 1);
        BinaryMembershipV1.Member memory m = membership.getMember(root);
        assertTrue(m.active);
        assertEq(m.sponsor, address(0));
    }

    function test_MemberRegistration() public {
        _registerRoot();

        vm.prank(users[0]);
        membership.register(root, root, BinaryMembershipV1.Side.Left);

        assertEq(membership.memberCount(), 2);
        BinaryMembershipV1.Member memory m = membership.getMember(users[0]);
        assertTrue(m.active);
        assertEq(m.sponsor, root);
    }

    function test_RevertDoubleRegistration() public {
        _registerRoot();

        vm.prank(users[0]);
        membership.register(root, root, BinaryMembershipV1.Side.Left);

        vm.expectRevert(BinaryMembershipV1.AlreadyRegistered.selector);
        vm.prank(users[0]);
        membership.register(root, root, BinaryMembershipV1.Side.Right);
    }

    function test_RevertInvalidSponsor() public {
        _registerRoot();

        vm.expectRevert(BinaryMembershipV1.SponsorNotRegistered.selector);
        vm.prank(users[0]);
        membership.register(users[1], root, BinaryMembershipV1.Side.Left);
    }

    function test_RevertSlotOccupied() public {
        _registerRoot();

        vm.prank(users[0]);
        membership.register(root, root, BinaryMembershipV1.Side.Left);

        vm.expectRevert(
            abi.encodeWithSelector(
                BinaryMembershipV1.SlotOccupied.selector,
                root,
                BinaryMembershipV1.Side.Left
            )
        );
        vm.prank(users[1]);
        membership.register(root, root, BinaryMembershipV1.Side.Left);
    }

    // ────────────────────────────────────────────────────────────────
    //  Fee splitting
    // ────────────────────────────────────────────────────────────────

    function test_FeeSplit() public {
        _registerRoot();

        uint256 rootBalBefore = token.balanceOf(root);

        vm.prank(users[0]);
        membership.register(root, root, BinaryMembershipV1.Side.Left);

        // Root should receive NODE_1 (5 ether) as direct parent
        uint256 rootBalAfter = token.balanceOf(root);
        assertEq(rootBalAfter - rootBalBefore, NODE_1);

        // Treasury portion should be pending
        assertEq(membership.pendingTreasury(), FEE_1 - NODE_1); // 15 ether
    }

    // ────────────────────────────────────────────────────────────────
    //  Binary tree placement
    // ────────────────────────────────────────────────────────────────

    function test_BinaryTreePlacement() public {
        _registerRoot();

        // Place left and right under root
        vm.prank(users[0]);
        membership.register(root, root, BinaryMembershipV1.Side.Left);

        vm.prank(users[1]);
        membership.register(root, root, BinaryMembershipV1.Side.Right);

        (address left, address right,,,,) = membership.getTreeInfo(root, 0);
        assertEq(left, users[0]);
        assertEq(right, users[1]);
    }

    function test_SpilloverPlacement() public {
        _registerRoot();

        // Root's direct slots filled
        vm.prank(users[0]);
        membership.register(root, root, BinaryMembershipV1.Side.Left);

        vm.prank(users[1]);
        membership.register(root, root, BinaryMembershipV1.Side.Right);

        // Spillover: user[2] sponsored by root but placed under user[0]
        vm.prank(users[2]);
        membership.register(root, users[0], BinaryMembershipV1.Side.Left);

        (address left,,,,, ) = membership.getTreeInfo(users[0], 0);
        assertEq(left, users[2]);

        // user[0] should have received the node reward for user[2]
        (,,,,, uint256 stageEarnings) = membership.getTreeInfo(users[0], 0);
        assertEq(stageEarnings, NODE_1);
    }

    // ────────────────────────────────────────────────────────────────
    //  Rollover
    // ────────────────────────────────────────────────────────────────

    function test_Stage1Rollover() public {
        _registerRoot();

        // Fill root's tree: 6 slots (2 levels of binary tree)
        // Level 1: users[0] (left), users[1] (right)
        vm.prank(users[0]);
        membership.register(root, root, BinaryMembershipV1.Side.Left);

        vm.prank(users[1]);
        membership.register(root, root, BinaryMembershipV1.Side.Right);

        // Level 2: users[2] under users[0].left, users[3] under users[0].right
        vm.prank(users[2]);
        membership.register(root, users[0], BinaryMembershipV1.Side.Left);

        vm.prank(users[3]);
        membership.register(root, users[0], BinaryMembershipV1.Side.Right);

        // users[4] under users[1].left, users[5] under users[1].right
        vm.prank(users[4]);
        membership.register(root, users[1], BinaryMembershipV1.Side.Left);

        // Before last slot: root should have 5 slots filled
        (,, uint256 slotsBefore, uint256 rolloverBefore,,) = membership.getTreeInfo(root, 0);
        assertEq(slotsBefore, 5);
        assertEq(rolloverBefore, 0);

        vm.prank(users[5]);
        membership.register(root, users[1], BinaryMembershipV1.Side.Right);

        // After 6th slot: root should have rolled over
        (address left, address right, uint256 slotsAfter, uint256 rolloverAfter,,) =
            membership.getTreeInfo(root, 0);
        assertEq(slotsAfter, 0);
        assertEq(rolloverAfter, 1);
        // Tree should be cleared for next cycle
        assertEq(left, address(0));
        assertEq(right, address(0));
    }

    // ────────────────────────────────────────────────────────────────
    //  Node reward payment
    // ────────────────────────────────────────────────────────────────

    function test_NodeRewardPaidToDirectParent() public {
        _registerRoot();

        uint256 rootBalBefore = token.balanceOf(root);

        // 6 members under root's tree
        vm.prank(users[0]);
        membership.register(root, root, BinaryMembershipV1.Side.Left);
        vm.prank(users[1]);
        membership.register(root, root, BinaryMembershipV1.Side.Right);

        // Only direct children pay root. Grandchildren pay their direct parents.
        uint256 rootEarned = token.balanceOf(root) - rootBalBefore;
        assertEq(rootEarned, NODE_1 * 2); // $5 x 2 direct children

        // users[0] gets paid when users[2] is placed under them
        uint256 user0BalBefore = token.balanceOf(users[0]);
        vm.prank(users[2]);
        membership.register(root, users[0], BinaryMembershipV1.Side.Left);
        uint256 user0Earned = token.balanceOf(users[0]) - user0BalBefore;
        assertEq(user0Earned, NODE_1);
    }

    // ────────────────────────────────────────────────────────────────
    //  Slot availability check
    // ────────────────────────────────────────────────────────────────

    function test_SlotAvailability() public {
        _registerRoot();

        assertTrue(membership.isSlotAvailable(root, 0, BinaryMembershipV1.Side.Left));
        assertTrue(membership.isSlotAvailable(root, 0, BinaryMembershipV1.Side.Right));

        vm.prank(users[0]);
        membership.register(root, root, BinaryMembershipV1.Side.Left);

        assertFalse(membership.isSlotAvailable(root, 0, BinaryMembershipV1.Side.Left));
        assertTrue(membership.isSlotAvailable(root, 0, BinaryMembershipV1.Side.Right));
    }

    // ────────────────────────────────────────────────────────────────
    //  Find open slot (BFS)
    // ────────────────────────────────────────────────────────────────

    function test_FindOpenSlot() public {
        _registerRoot();

        // Root has both slots open, should return left
        (address parent, BinaryMembershipV1.Side side) = membership.findOpenSlot(root, 0);
        assertEq(parent, root);
        assertTrue(side == BinaryMembershipV1.Side.Left);

        // Fill left
        vm.prank(users[0]);
        membership.register(root, root, BinaryMembershipV1.Side.Left);

        // Should return right now
        (parent, side) = membership.findOpenSlot(root, 0);
        assertEq(parent, root);
        assertTrue(side == BinaryMembershipV1.Side.Right);

        // Fill right
        vm.prank(users[1]);
        membership.register(root, root, BinaryMembershipV1.Side.Right);

        // Should BFS to users[0].left
        (parent, side) = membership.findOpenSlot(root, 0);
        assertEq(parent, users[0]);
        assertTrue(side == BinaryMembershipV1.Side.Left);
    }

    // ────────────────────────────────────────────────────────────────
    //  Stage progression
    // ────────────────────────────────────────────────────────────────

    function test_JoinStage2_RevertWithoutEnrolledParent() public {
        _registerRoot();
        _fillStage1ForRoot();

        // users[0] is enrolled in stage 0 but not stage 1
        // Trying to join stage 1 under a non-enrolled parent should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                BinaryMembershipV1.ParentNotInStage.selector,
                users[0],
                1
            )
        );
        vm.prank(users[1]);
        membership.joinStage(1, users[0], BinaryMembershipV1.Side.Left);
    }

    function test_RevertJoinStageWithoutPrevious() public {
        _registerRoot();

        // users[0] is not registered at all
        vm.expectRevert(BinaryMembershipV1.NotRegistered.selector);
        vm.prank(users[0]);
        membership.joinStage(1, root, BinaryMembershipV1.Side.Left);
    }

    function test_RevertJoinStageSkipped() public {
        _registerRoot();

        // Register users[0] in stage 0
        vm.prank(users[0]);
        membership.register(root, root, BinaryMembershipV1.Side.Left);

        // Try to skip to stage 2 (index 2) without joining stage 1 (index 1)
        vm.expectRevert(
            abi.encodeWithSelector(
                BinaryMembershipV1.PreviousStageRequired.selector,
                1
            )
        );
        vm.prank(users[0]);
        membership.joinStage(2, root, BinaryMembershipV1.Side.Left);
    }

    // ────────────────────────────────────────────────────────────────
    //  Physical awards
    // ────────────────────────────────────────────────────────────────

    function test_RevertAwardBeforeRollovers() public {
        _registerRoot();

        vm.expectRevert(
            abi.encodeWithSelector(
                BinaryMembershipV1.InvalidStage.selector,
                0
            )
        );
        vm.prank(operator);
        membership.grantPhysicalAward(root, 0, 100 ether);
    }

    // ────────────────────────────────────────────────────────────────
    //  Treasury
    // ────────────────────────────────────────────────────────────────

    function test_TreasuryWithdraw() public {
        _registerRoot();

        vm.prank(users[0]);
        membership.register(root, root, BinaryMembershipV1.Side.Left);

        uint256 pending = membership.pendingTreasury();
        assertEq(pending, FEE_1 - NODE_1); // 15 ether

        uint256 treasuryBalBefore = token.balanceOf(treasury);
        vm.prank(treasury);
        membership.withdrawTreasury(pending);

        assertEq(token.balanceOf(treasury) - treasuryBalBefore, pending);
        assertEq(membership.pendingTreasury(), 0);
    }

    function test_RevertTreasuryOverWithdraw() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                BinaryMembershipV1.InsufficientPendingTreasury.selector,
                0,
                1 ether
            )
        );
        vm.prank(treasury);
        membership.withdrawTreasury(1 ether);
    }

    // ────────────────────────────────────────────────────────────────
    //  Pause
    // ────────────────────────────────────────────────────────────────

    function test_PauseBlocksRegistration() public {
        vm.prank(pauser);
        membership.pause();

        vm.expectRevert();
        vm.prank(root);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);
    }

    // ────────────────────────────────────────────────────────────────
    //  Weekly sponsor tracking
    // ────────────────────────────────────────────────────────────────

    function test_WeeklySponsorTracking() public {
        _registerRoot();

        vm.prank(users[0]);
        membership.register(root, root, BinaryMembershipV1.Side.Left);

        vm.prank(users[1]);
        membership.register(root, root, BinaryMembershipV1.Side.Right);

        assertEq(membership.getCurrentWeekSponsorCount(root), 2);
    }

    // ────────────────────────────────────────────────────────────────
    //  Config
    // ────────────────────────────────────────────────────────────────

    function test_RevertDoubleConfig() public {
        vm.expectRevert(BinaryMembershipV1.StagesAlreadyConfigured.selector);
        vm.prank(admin);
        membership.configureStages(
            [FEE_1, FEE_2, FEE_3, FEE_4, FEE_5, FEE_6],
            [NODE_1, NODE_2, NODE_3, NODE_4, NODE_5, NODE_6],
            [uint256(6), 14, 14, 14, 14, 14],
            [uint256(2), 3, 3, 3, 3, 3],
            [uint256(0), 10, 10, 10, 10, 8]
        );
    }

    function test_SetTreasury() public {
        address newTreasury = address(0xBEEF);
        vm.prank(admin);
        membership.setTreasury(newTreasury);
        assertEq(membership.treasury(), newTreasury);
    }

    // ────────────────────────────────────────────────────────────────
    //  Admin: updateStageFee
    // ────────────────────────────────────────────────────────────────

    function test_UpdateStageFee() public {
        _registerRoot();

        uint256 newFee = 30 ether;
        uint256 newNode = 8 ether;
        vm.prank(admin);
        membership.updateStageFee(0, newFee, newNode);

        BinaryMembershipV1.StageConfig memory config = membership.getStageConfig(0);
        assertEq(config.fee, newFee);
        assertEq(config.nodeReward, newNode);

        // New fee applies to next registration
        uint256 rootBalBefore = token.balanceOf(root);
        vm.prank(users[0]);
        membership.register(root, root, BinaryMembershipV1.Side.Left);

        assertEq(token.balanceOf(root) - rootBalBefore, newNode);
        assertEq(membership.pendingTreasury(), newFee - newNode);
    }

    function test_RevertUpdateStageFee_InvalidConfig() public {
        vm.expectRevert(BinaryMembershipV1.InvalidFeeConfig.selector);
        vm.prank(admin);
        membership.updateStageFee(0, 10 ether, 10 ether); // nodeReward == fee
    }

    function test_RevertUpdateStageFee_NotAdmin() public {
        vm.expectRevert();
        vm.prank(operator);
        membership.updateStageFee(0, 30 ether, 8 ether);
    }

    // ────────────────────────────────────────────────────────────────
    //  Admin: updateAwardThreshold
    // ────────────────────────────────────────────────────────────────

    function test_UpdateAwardThreshold() public {
        vm.prank(admin);
        membership.updateAwardThreshold(1, 3);

        BinaryMembershipV1.StageConfig memory config = membership.getStageConfig(1);
        assertEq(config.rolloversForAward, 3);
    }

    function test_RevertUpdateAwardThreshold_NotAdmin() public {
        vm.expectRevert();
        vm.prank(operator);
        membership.updateAwardThreshold(1, 3);
    }

    // ────────────────────────────────────────────────────────────────
    //  Admin: setStageOpen / stageClosed
    // ────────────────────────────────────────────────────────────────

    function test_StageClosedBlocksJoin() public {
        _registerRoot();

        vm.prank(admin);
        membership.setStageOpen(0, false);
        assertTrue(membership.stageClosed(0));

        vm.expectRevert(
            abi.encodeWithSelector(BinaryMembershipV1.StageClosed.selector, 0)
        );
        vm.prank(users[0]);
        membership.register(root, root, BinaryMembershipV1.Side.Left);

        // Reopen
        vm.prank(admin);
        membership.setStageOpen(0, true);
        assertFalse(membership.stageClosed(0));

        vm.prank(users[0]);
        membership.register(root, root, BinaryMembershipV1.Side.Left);
        assertEq(membership.memberCount(), 2);
    }

    // ────────────────────────────────────────────────────────────────
    //  Admin: cycle guard
    // ────────────────────────────────────────────────────────────────

    function test_CycleGuardAllowsDetachedBoardWithoutCreditingAncestor() public {
        _registerRoot();

        // Enable cycle guard
        vm.prank(admin);
        membership.setCycleGuardEnabled(true);
        assertTrue(membership.cycleGuardEnabled());

        // Fill root's tree to trigger rollover (6 members)
        _fillStage1ForRoot();

        // Root has rolled over — users[0] was root.left but now orphaned
        (address left,,,,, ) = membership.getTreeInfo(root, 0);
        assertEq(left, address(0), "root.left should be cleared after rollover");

        BinaryMembershipV1.StageMembership memory rootBefore =
            membership.getStageMembership(root, 0);

        // users[2] remains inside users[0]'s detached board. The stale
        // users[0] -> root edge is now an independent board boundary.
        vm.prank(users[6]);
        membership.register(root, users[2], BinaryMembershipV1.Side.Left);

        BinaryMembershipV1.StageMembership memory rootAfter =
            membership.getStageMembership(root, 0);
        assertTrue(membership.getMember(users[6]).active, "detached placement failed");
        assertEq(rootAfter.slotsFilledBelow, rootBefore.slotsFilledBelow, "former ancestor credited");
        assertEq(rootAfter.rolloverCount, rootBefore.rolloverCount, "former ancestor rolled");
    }

    function test_CycleGuardDisabledAllowsOrphanedParent() public {
        _registerRoot();

        // Guard is off by default
        assertFalse(membership.cycleGuardEnabled());

        _fillStage1ForRoot();

        // users[2] is a leaf under users[0] — orphaned from root after rollover
        // but still has open slots (no children)
        vm.prank(users[6]);
        membership.register(root, users[2], BinaryMembershipV1.Side.Left);
        assertEq(membership.memberCount(), 8);
    }

    function test_CycleGuardToggle() public {
        vm.prank(admin);
        membership.setCycleGuardEnabled(true);
        assertTrue(membership.cycleGuardEnabled());

        vm.prank(admin);
        membership.setCycleGuardEnabled(false);
        assertFalse(membership.cycleGuardEnabled());
    }

    // ────────────────────────────────────────────────────────────────
    //  Helpers
    // ────────────────────────────────────────────────────────────────

    function _registerRoot() internal {
        vm.prank(root);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);
    }

    function _fillStage1ForRoot() internal {
        // Fill 6 slots under root for stage 1
        vm.prank(users[0]);
        membership.register(root, root, BinaryMembershipV1.Side.Left);
        vm.prank(users[1]);
        membership.register(root, root, BinaryMembershipV1.Side.Right);
        vm.prank(users[2]);
        membership.register(root, users[0], BinaryMembershipV1.Side.Left);
        vm.prank(users[3]);
        membership.register(root, users[0], BinaryMembershipV1.Side.Right);
        vm.prank(users[4]);
        membership.register(root, users[1], BinaryMembershipV1.Side.Left);
        vm.prank(users[5]);
        membership.register(root, users[1], BinaryMembershipV1.Side.Right);
    }
}
