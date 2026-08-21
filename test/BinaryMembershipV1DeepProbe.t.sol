// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Deep probe of behaviours the analyzers cannot see, because none of
///         them are memory-safety or arithmetic faults — they are questions
///         about privilege, configuration and spec intent.
///
///  Each test either demonstrates a live gap or pins down behaviour that
///  should be a deliberate decision rather than an accident.
contract BinaryMembershipV1DeepProbeTest is Test {
    BinaryMembershipV1 public membership;
    MockERC20 public token;

    address admin    = address(0xAD);
    address treasury = address(0x7EA5);
    address operator = address(0x0B);

    address legitRoot = address(0x1);
    address attacker  = address(0xBAD);
    address alice     = address(0xA11CE);
    address bob       = address(0xB0B);

    uint256[6] FEES   = [uint256(20 ether), 60 ether, 180 ether, 540 ether, 1620 ether, 4860 ether];
    uint256[6] NODES  = [uint256(5 ether), 10 ether, 25 ether, 80 ether, 250 ether, 800 ether];
    uint256[6] SLOTS  = [uint256(6), 14, 14, 14, 14, 14];
    uint256[6] DEPTHS = [uint256(2), 3, 3, 3, 3, 3];
    uint256[6] AWARDS = [uint256(0), 10, 10, 10, 10, 8];

    function setUp() public {
        token = new MockERC20("FAKEUSD", "FUSD", 0);

        vm.startPrank(admin);
        membership = new BinaryMembershipV1(IERC20(address(token)), treasury, admin, 0, legitRoot);
        membership.grantRole(membership.OPERATOR_ROLE(), operator);
        membership.grantRole(membership.TREASURY_ROLE(), treasury);
        membership.configureStages(FEES, NODES, SLOTS, DEPTHS, AWARDS);
        vm.stopPrank();

        address[4] memory who = [legitRoot, attacker, alice, bob];
        for (uint256 i = 0; i < who.length; i++) {
            token.mint(who[i], 100_000 ether);
            vm.prank(who[i]);
            token.approve(address(membership), type(uint256).max);
        }
        token.mint(address(membership), 1_000_000 ether);
    }

    // ══════════════════════════════════════════════════════════════════
    //  PROBE 1 — the system root position is unowned and first-come
    // ══════════════════════════════════════════════════════════════════

    /// @notice REGRESSION. `register` used to hand the root position to whoever
    ///         called first, for free, because it decided on `memberCount == 0`
    ///         alone. The root is the most valuable position in the system —
    ///         the 1,000-wallet run measured it capturing 60% of the stage-0
    ///         pool — so the window between deployment and the root's first
    ///         transaction was worth front-running.
    ///
    ///  It is now pinned to `designatedRoot`, fixed at construction.
    function test_Probe_RootPositionCannotBeFrontRun() public {
        vm.prank(attacker);
        vm.expectRevert(BinaryMembershipV1.NotDesignatedRoot.selector);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);

        assertFalse(
            membership.getStageMembership(attacker, 0).enrolled,
            "attacker took the root position"
        );
        assertEq(membership.memberCount(), 0, "a member was created");

        // The designated root still takes it normally, and still pays nothing.
        vm.prank(legitRoot);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);

        assertTrue(membership.getStageMembership(legitRoot, 0).enrolled, "root not enrolled");
        assertEq(token.balanceOf(legitRoot), 100_000 ether, "root was charged a fee");
        assertEq(membership.designatedRoot(), legitRoot, "designatedRoot mismatch");
    }

    /// @notice The pin only governs the root slot. Once it is taken, the
    ///         ordinary registration path is unaffected for everyone else.
    function test_Probe_DesignatedRootDoesNotBlockNormalRegistration() public {
        vm.prank(legitRoot);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);

        vm.prank(attacker);
        membership.register(legitRoot, legitRoot, BinaryMembershipV1.Side.Left);

        assertEq(
            membership.getStageMembership(attacker, 0).parent,
            legitRoot,
            "normal registration broke"
        );
    }

    // ══════════════════════════════════════════════════════════════════
    //  PROBE 2 — enrollStageRoot is a fee bypass for arbitrary members
    // ══════════════════════════════════════════════════════════════════

    /// @notice The docstring says this enrolls "the system root", but nothing
    ///         checks that. Any OPERATOR_ROLE holder can enrol any registered
    ///         member into stages 1-5 free of charge, skipping $60 + $180 +
    ///         $540 + $1,620 + $4,860 = $7,260 of fees per member.
    function test_Probe_EnrollStageRootBypassesAllStageFees() public {
        vm.prank(legitRoot);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);

        vm.prank(alice);
        membership.register(legitRoot, legitRoot, BinaryMembershipV1.Side.Left);

        uint256 balanceBefore = token.balanceOf(alice);

        // Alice is an ordinary member, not the system root.
        vm.startPrank(operator);
        for (uint256 s = 1; s < 6; s++) {
            membership.enrollStageRoot(alice, s);
        }
        vm.stopPrank();

        for (uint256 s = 1; s < 6; s++) {
            assertTrue(
                membership.getStageMembership(alice, s).enrolled,
                "alice should be enrolled"
            );
        }

        assertEq(token.balanceOf(alice), balanceBefore, "alice paid something");

        uint256 bypassed;
        for (uint256 s = 1; s < 6; s++) bypassed += FEES[s];
        console.log("stage fees bypassed for one member (USD):", bypassed / 1 ether);
        console.log("contract recorded fees for them   (USD):", uint256(0));
    }

    /// @notice The bypass is not merely free entry — the member becomes a board
    ///         owner at that stage and earns from everyone placed beneath them.
    function test_Probe_BypassedMemberThenEarnsAsBoardOwner() public {
        vm.prank(legitRoot);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);
        vm.prank(alice);
        membership.register(legitRoot, legitRoot, BinaryMembershipV1.Side.Left);
        vm.prank(bob);
        membership.register(legitRoot, legitRoot, BinaryMembershipV1.Side.Right);

        // Alice gets stage 1 free; Bob pays for it.
        vm.prank(operator);
        membership.enrollStageRoot(alice, 1);

        vm.prank(bob);
        membership.joinStage(1, alice, BinaryMembershipV1.Side.Left);

        assertEq(
            membership.getStageMembership(alice, 1).stageEarnings,
            NODES[1],
            "free rider should still be paid"
        );
        console.log("earned by fee-free board owner (USD):",
            membership.getStageMembership(alice, 1).stageEarnings / 1 ether);
    }

    // ══════════════════════════════════════════════════════════════════
    //  PROBE 3 — treeSlots and treeDepth are never checked against each other
    // ══════════════════════════════════════════════════════════════════

    /// @notice REGRESSION. `configureStages` is one-time and has no setter for
    ///         either field afterwards, yet it used to accept any (treeSlots,
    ///         treeDepth) pair. A binary board of depth d holds 2^(d+1)-2 slots
    ///         — 6 at depth 2, 14 at depth 3 — and a mismatched pair is
    ///         permanent: too many slots makes rollover unreachable, too few
    ///         fires it before the board is full.
    function test_Probe_ConfigureStagesRejectsImpossibleBoardGeometry() public {
        MockERC20 t2 = new MockERC20("F2", "F2", 0);

        vm.startPrank(admin);
        BinaryMembershipV1 m2 =
            new BinaryMembershipV1(IERC20(address(t2)), treasury, admin, 0, legitRoot);

        // depth 2 can only reach 6 positions, but this claims a 14-slot board.
        uint256[6] memory badSlots = [uint256(14), 14, 14, 14, 14, 14];
        uint256[6] memory badDepths = [uint256(2), 3, 3, 3, 3, 3];

        vm.expectRevert(
            abi.encodeWithSelector(
                BinaryMembershipV1.InvalidBoardGeometry.selector, 0, 14, 2
            )
        );
        m2.configureStages(FEES, NODES, badSlots, badDepths, AWARDS);

        // Too few slots for the depth is rejected on the same rule.
        uint256[6] memory tooFew = [uint256(6), 6, 14, 14, 14, 14];
        vm.expectRevert(
            abi.encodeWithSelector(
                BinaryMembershipV1.InvalidBoardGeometry.selector, 1, 6, 3
            )
        );
        m2.configureStages(FEES, NODES, tooFew, DEPTHS, AWARDS);

        // An absurd depth is bounded rather than left to overflow the shift.
        uint256[6] memory deep = [uint256(6), 14, 14, 14, 14, 14];
        uint256[6] memory absurd = [uint256(2), 3, 3, 3, 3, 999];
        vm.expectRevert(
            abi.encodeWithSelector(
                BinaryMembershipV1.InvalidBoardGeometry.selector, 5, 14, 999
            )
        );
        m2.configureStages(FEES, NODES, deep, absurd, AWARDS);

        // The shipped geometry still configures cleanly.
        m2.configureStages(FEES, NODES, SLOTS, DEPTHS, AWARDS);
        vm.stopPrank();

        BinaryMembershipV1.StageConfig memory c = m2.getStageConfig(0);
        assertEq(c.treeSlots, 6, "stage 0 slots");
        assertEq(c.treeDepth, 2, "stage 0 depth");
    }

    // ══════════════════════════════════════════════════════════════════
    //  PROBE 4 — awards repeat every N rollovers
    // ══════════════════════════════════════════════════════════════════

    /// @notice Awards are repeatable: every `rolloversForAward` additional
    ///         rollovers unlock another award. A member with 20 rollovers at
    ///         threshold 10 can claim twice; at high volume they can claim
    ///         many times, each advancing `lastAwardedRollover`.
    function test_Probe_AwardRepeatsEveryNRollovers() public {
        vm.prank(legitRoot);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);

        address[] memory crowd = new address[](300);
        for (uint256 i = 0; i < 300; i++) {
            crowd[i] = address(uint160(0x500000 + i));
            token.mint(crowd[i], 100_000 ether);
            vm.prank(crowd[i]);
            token.approve(address(membership), type(uint256).max);

            (address p, BinaryMembershipV1.Side side) = membership.findOpenSlot(legitRoot, 0);
            vm.prank(crowd[i]);
            membership.register(legitRoot, p, side);
        }

        vm.prank(operator);
        membership.enrollStageRoot(legitRoot, 1);
        for (uint256 i = 0; i < 280; i++) {
            (address p, BinaryMembershipV1.Side side) = membership.findOpenSlot(legitRoot, 1);
            vm.prank(crowd[i]);
            membership.joinStage(1, p, side);
        }

        uint256 rollovers = membership.getStageMembership(legitRoot, 1).rolloverCount;
        assertGe(rollovers, AWARDS[1] * 2, "need enough rollovers for at least 2 awards");

        // First award at milestone 10
        vm.prank(operator);
        membership.grantPhysicalAward(legitRoot, 1, 1 ether);

        (,,,, uint256 lastAwarded1,) = membership.getTreeInfo(legitRoot, 1);
        assertEq(lastAwarded1, AWARDS[1], "first award milestone");

        // Second award is immediately available at milestone 20.
        vm.prank(operator);
        membership.grantPhysicalAward(legitRoot, 1, 1 ether);

        (,,,, uint256 lastAwarded2,) = membership.getTreeInfo(legitRoot, 1);
        assertEq(lastAwarded2, AWARDS[1] * 2, "second award milestone");

        // Third award requires rollover 30 — not enough.
        vm.expectRevert(
            abi.encodeWithSelector(
                BinaryMembershipV1.RolloversNotMet.selector, AWARDS[1] * 3, rollovers
            )
        );
        vm.prank(operator);
        membership.grantPhysicalAward(legitRoot, 1, 1 ether);

        assertEq(membership.getAwardRecordCount(), 2, "should have 2 award records");

        console.log("rollovers achieved  :", rollovers);
        console.log("threshold per stage :", AWARDS[1]);
        console.log("awards claimed      :", uint256(2));
    }

    // ══════════════════════════════════════════════════════════════════
    //  PROBE 5 — pause does not stop the admin surface
    // ══════════════════════════════════════════════════════════════════

    /// @notice REGRESSION. `whenNotPaused` used to guard register and joinStage
    ///         only, leaving treasury withdrawal and award granting live while
    ///         paused — the wrong way round for incident response, which wants
    ///         value movement frozen first. Both are now paused too.
    function test_Probe_PauseHaltsTreasuryAndAwards() public {
        vm.prank(legitRoot);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);
        vm.prank(alice);
        membership.register(legitRoot, legitRoot, BinaryMembershipV1.Side.Left);

        bytes32 pauserRole = membership.PAUSER_ROLE();
        vm.startPrank(admin);
        membership.grantRole(pauserRole, admin);
        membership.pause();
        vm.stopPrank();

        // Users are stopped.
        vm.prank(bob);
        vm.expectRevert();
        membership.register(legitRoot, legitRoot, BinaryMembershipV1.Side.Right);

        // Treasury is stopped too.
        uint256 pending = membership.pendingTreasury();
        assertGt(pending, 0, "no treasury to test with");
        vm.prank(treasury);
        vm.expectRevert();
        membership.withdrawTreasury(pending);
        assertEq(token.balanceOf(treasury), 0, "funds left while paused");

        // Awards are stopped too.
        vm.prank(operator);
        vm.expectRevert();
        membership.grantPhysicalAward(alice, 1, 0);

        // Unpausing restores both.
        vm.prank(admin);
        membership.unpause();
        vm.prank(treasury);
        membership.withdrawTreasury(pending);
        assertEq(token.balanceOf(treasury), pending, "withdrawal broken after unpause");

        console.log("held back while paused, released after (USD):", pending / 1 ether);
    }
}
