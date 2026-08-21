// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BinaryMembershipV1FuzzTest is Test {
    BinaryMembershipV1 public membership;
    MockERC20 public token;

    address admin = address(0xAD);
    address treasury = address(0x7777);
    address operator = address(0x8888);

    uint256 constant FEE_1 = 20 ether;
    uint256 constant FEE_2 = 60 ether;
    uint256 constant FEE_3 = 180 ether;
    uint256 constant FEE_4 = 540 ether;
    uint256 constant FEE_5 = 1620 ether;
    uint256 constant FEE_6 = 4860 ether;

    uint256 constant NODE_1 = 5 ether;
    uint256 constant NODE_2 = 10 ether;
    uint256 constant NODE_3 = 25 ether;
    uint256 constant NODE_4 = 80 ether;
    uint256 constant NODE_5 = 250 ether;
    uint256 constant NODE_6 = 800 ether;

    address root = address(0x1);

    function setUp() public {
        token = new MockERC20("FAKEUSD", "FUSD", 18);

        vm.startPrank(admin);
        membership = new BinaryMembershipV1(
            IERC20(address(token)), treasury, admin, 0, root
        );
        membership.grantRole(membership.OPERATOR_ROLE(), operator);
        membership.grantRole(membership.TREASURY_ROLE(), treasury);

        membership.configureStages(
            [FEE_1, FEE_2, FEE_3, FEE_4, FEE_5, FEE_6],
            [NODE_1, NODE_2, NODE_3, NODE_4, NODE_5, NODE_6],
            [uint256(6), 14, 14, 14, 14, 14],
            [uint256(2), 3, 3, 3, 3, 3],
            [uint256(0), 10, 10, 10, 10, 8]
        );
        vm.stopPrank();

        // Register root
        vm.prank(root);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);

        // Fund contract for payouts
        token.mint(address(membership), 10_000_000 ether);
    }

    function _makeUser(uint256 seed) internal returns (address user) {
        user = address(uint160(bound(seed, 0x1000, type(uint160).max)));
        vm.assume(user != root && user != admin && user != treasury && user != operator);
        // The contracts themselves must never be fuzzed in as a member: pulling
        // a fee from the membership contract is a self-transfer that nets to
        // zero and trips TransferAmountMismatch. Unreachable in production
        // (the contract never calls register) but reachable by the fuzzer.
        vm.assume(user != address(membership) && user != address(token));
        vm.assume(!membership.getMember(user).active);
        token.mint(user, 100_000 ether);
        vm.prank(user);
        token.approve(address(membership), type(uint256).max);
    }

    // ── Fuzz 1: Fee split is always correct ──────────────────────────

    function testFuzz_FeeSplitAlwaysCorrect(uint256 seed) public {
        address user = _makeUser(seed);

        uint256 contractBalBefore = token.balanceOf(address(membership));
        uint256 rootBalBefore = token.balanceOf(root);
        uint256 pendingBefore = membership.pendingTreasury();

        vm.prank(user);
        membership.register(root, root, BinaryMembershipV1.Side.Left);

        uint256 nodeRewardPaid = token.balanceOf(root) - rootBalBefore;
        uint256 treasuryAccumulated = membership.pendingTreasury() - pendingBefore;

        assertEq(nodeRewardPaid, NODE_1, "node reward mismatch");
        assertEq(treasuryAccumulated, FEE_1 - NODE_1, "treasury split mismatch");
        assertEq(nodeRewardPaid + treasuryAccumulated, FEE_1, "total fee mismatch");
    }

    // ── Fuzz 2: Random non-member sponsor always reverts ─────────────

    function testFuzz_RegisterWithRandomSponsor(address sponsor) public {
        vm.assume(sponsor != address(0));
        vm.assume(!membership.getMember(sponsor).active);

        address user = address(uint160(uint256(keccak256(abi.encode(sponsor))) | 0x10000));
        vm.assume(user != root && user != admin && user != treasury && user != operator);
        token.mint(user, 100_000 ether);
        vm.prank(user);
        token.approve(address(membership), type(uint256).max);

        vm.expectRevert(BinaryMembershipV1.SponsorNotRegistered.selector);
        vm.prank(user);
        membership.register(sponsor, root, BinaryMembershipV1.Side.Left);
    }

    // ── Fuzz 3: Invalid stage always reverts ─────────────────────────

    function testFuzz_CannotJoinInvalidStage(uint256 stageId) public {
        stageId = bound(stageId, 6, type(uint256).max);

        address user = _makeUser(uint256(keccak256(abi.encode(stageId))));

        vm.prank(user);
        membership.register(root, root, BinaryMembershipV1.Side.Left);

        vm.expectRevert(abi.encodeWithSelector(BinaryMembershipV1.InvalidStage.selector, stageId));
        vm.prank(user);
        membership.joinStage(stageId, root, BinaryMembershipV1.Side.Left);
    }

    // ── Fuzz 4: Double slot always reverts ───────────────────────────

    function testFuzz_SlotOccupiedAlwaysReverts(uint8 sideRaw) public {
        BinaryMembershipV1.Side side = sideRaw % 2 == 0
            ? BinaryMembershipV1.Side.Left
            : BinaryMembershipV1.Side.Right;

        address user1 = _makeUser(1001);
        address user2 = _makeUser(2002);

        vm.prank(user1);
        membership.register(root, root, side);

        vm.expectRevert(
            abi.encodeWithSelector(BinaryMembershipV1.SlotOccupied.selector, root, side)
        );
        vm.prank(user2);
        membership.register(root, root, side);
    }

    // ── Fuzz 5: Node reward matches stage config ─────────────────────

    function testFuzz_NodeRewardMatchesConfig(uint256 seed) public {
        address user = _makeUser(seed);

        uint256 rootBalBefore = token.balanceOf(root);

        vm.prank(user);
        membership.register(root, root, BinaryMembershipV1.Side.Left);

        uint256 paid = token.balanceOf(root) - rootBalBefore;
        BinaryMembershipV1.StageConfig memory config = membership.getStageConfig(0);
        assertEq(paid, config.nodeReward, "reward != config.nodeReward");
    }

    // ── Fuzz 6: Rollover at exact slot count ─────────────────────────

    function testFuzz_RolloverAtExactSlotCount(uint256 extraSeed) public {
        // Fill root's tree with 5 members (not yet full)
        for (uint256 i = 0; i < 5; i++) {
            address user = _makeUser(3000 + i);
            (address parent, BinaryMembershipV1.Side side) = membership.findOpenSlot(root, 0);
            vm.prank(user);
            membership.register(root, parent, side);
        }

        (,, uint256 slots, uint256 rollovers,,) = membership.getTreeInfo(root, 0);
        assertEq(slots, 5, "should have 5 slots filled");
        assertEq(rollovers, 0, "should not have rolled over yet");

        // Fill 6th slot
        address lastUser = _makeUser(4000);
        (address parent, BinaryMembershipV1.Side side) = membership.findOpenSlot(root, 0);
        vm.prank(lastUser);
        membership.register(root, parent, side);

        (,, uint256 slotsAfter, uint256 rolloversAfter,,) = membership.getTreeInfo(root, 0);
        assertEq(slotsAfter, 0, "slots should reset after rollover");
        assertEq(rolloversAfter, 1, "should have rolled over once");
    }

    // ── Fuzz 7: Pending treasury never exceeds contract balance ──────

    function testFuzz_PendingTreasuryNeverExceedsBalance(uint256 numJoins) public {
        numJoins = bound(numJoins, 1, 20);

        for (uint256 i = 0; i < numJoins; i++) {
            address user = _makeUser(5000 + i);
            (address parent, BinaryMembershipV1.Side side) = membership.findOpenSlot(root, 0);
            vm.prank(user);
            membership.register(root, parent, side);
        }

        assertLe(
            membership.pendingTreasury(),
            token.balanceOf(address(membership)),
            "pendingTreasury > contract balance"
        );
    }

    // ── Fuzz 8: Weekly count is monotonic ────────────────────────────

    function testFuzz_WeeklyCountMonotonic(uint256 numJoins) public {
        numJoins = bound(numJoins, 1, 15);

        uint256 prevCount = membership.getCurrentWeekSponsorCount(root);

        for (uint256 i = 0; i < numJoins; i++) {
            address user = _makeUser(6000 + i);
            (address parent, BinaryMembershipV1.Side side) = membership.findOpenSlot(root, 0);
            vm.prank(user);
            membership.register(root, parent, side);

            uint256 newCount = membership.getCurrentWeekSponsorCount(root);
            assertGe(newCount, prevCount, "weekly count decreased");
            prevCount = newCount;
        }
    }
}
