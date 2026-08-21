// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice 1,000-wallet aggressive stress across the FULL six-stage ladder.
///
///  The centrepiece is a ghost model: an independent reimplementation of the
///  spec's payout and rollover rules, built from the handwritten plan rather
///  than from `BinaryMembershipV1`. Every placement is scored twice — once by
///  the contract, once by the ghost — and the two are compared. A logic bug
///  therefore surfaces as a divergence rather than being read back and
///  silently confirmed.
///
///  Covers: BFS spillover shape, spillunder earnings, rollover cycling with
///  the board-depth cap, upline payment at every level, the award cap gate,
///  treasury accounting, and global token conservation.
contract BinaryMembershipV1Stress1000Test is Test {
    BinaryMembershipV1 public membership;
    MockERC20 public token;

    address admin     = address(0xAD);
    address treasury  = address(0x7EA5);
    address operator  = address(0x0B);
    address pauser    = address(0x9999);

    address root = address(0x1);
    address[] public users;

    uint256 constant WALLETS = 1000;

    // Stage spec, straight from the plan sheets.
    uint256[6] FEES   = [uint256(20 ether), 60 ether, 180 ether, 540 ether, 1620 ether, 4860 ether];
    uint256[6] NODES  = [uint256(5 ether), 10 ether, 25 ether, 80 ether, 250 ether, 800 ether];
    uint256[6] SLOTS  = [uint256(6), 14, 14, 14, 14, 14];
    uint256[6] DEPTHS = [uint256(2), 3, 3, 3, 3, 3];
    uint256[6] AWARDS = [uint256(0), 10, 10, 10, 10, 8];

    // Members per stage. Nested subsets, because stage N requires stage N-1.
    uint256[6] JOINS = [uint256(1000), 700, 350, 168, 84, 42];

    uint256 constant SEED = 20_000_000 ether;
    uint256 constant FUND = 50_000 ether;

    // ── Ghost model state (mirrors the spec, never the contract) ──────
    mapping(address => mapping(uint256 => address)) ghostParent;
    mapping(address => mapping(uint256 => uint256)) ghostSlots;
    mapping(address => mapping(uint256 => uint256)) ghostRollovers;
    mapping(address => mapping(uint256 => uint256)) ghostEarnings;
    mapping(address => mapping(uint256 => bool))    ghostEnrolled;

    uint256 ghostFees;
    uint256 ghostPool;
    uint256 ghostTreasury;
    uint256 ghostWithdrawn;
    uint256 ghostAwards;

    // Per-stage tallies for reporting.
    uint256[6] statPlacements;
    uint256[6] statPool;
    uint256[6] statRollovers;

    function setUp() public {
        token = new MockERC20("FAKEUSD", "FUSD", 0);

        vm.startPrank(admin);
        membership = new BinaryMembershipV1(IERC20(address(token)), treasury, admin, 0, root);
        membership.grantRole(membership.OPERATOR_ROLE(), operator);
        membership.grantRole(membership.TREASURY_ROLE(), treasury);
        membership.grantRole(membership.PAUSER_ROLE(), pauser);
        membership.configureStages(FEES, NODES, SLOTS, DEPTHS, AWARDS);
        vm.stopPrank();

        for (uint256 i = 0; i < WALLETS; i++) {
            address u = address(uint160(0x200000 + i));
            users.push(u);
            token.mint(u, FUND);
            vm.prank(u);
            token.approve(address(membership), type(uint256).max);
        }

        token.mint(root, FUND);
        vm.prank(root);
        token.approve(address(membership), type(uint256).max);

        token.mint(address(membership), SEED);

        vm.prank(root);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);
        ghostEnrolled[root][0] = true;
    }

    // ══════════════════════════════════════════════════════════════════
    //  Ghost model — the spec, reimplemented independently
    // ══════════════════════════════════════════════════════════════════

    /// @dev Score a placement the way the plan says it should be scored:
    ///      every upline whose board this lands on receives one full
    ///      nodeReward, and a board is `treeDepth` levels deep.
    function _ghostPlace(address member, address parent, uint256 s)
        internal
        returns (uint256 expectedPayout)
    {
        uint256 levels;
        address cur = parent;
        while (cur != address(0) && levels < DEPTHS[s]) {
            ghostEarnings[cur][s] += NODES[s];
            levels++;
            cur = ghostParent[cur][s];
        }
        expectedPayout = levels * NODES[s];

        // Credit the placement to each board it lands on, same depth cap.
        cur = parent;
        for (uint256 l = 0; l < DEPTHS[s] && cur != address(0); l++) {
            ghostSlots[cur][s]++;
            if (ghostSlots[cur][s] >= SLOTS[s]) {
                ghostRollovers[cur][s]++;
                ghostSlots[cur][s] = 0;
            }
            cur = ghostParent[cur][s];
        }

        ghostParent[member][s] = parent;
        ghostEnrolled[member][s] = true;

        ghostFees += FEES[s];
        ghostPool += expectedPayout;
        ghostTreasury += FEES[s] - expectedPayout;

        statPlacements[s]++;
        statPool[s] += expectedPayout;
    }

    function _usd(uint256 x) internal pure returns (uint256) { return x / 1 ether; }

    // ══════════════════════════════════════════════════════════════════
    //  MAIN: full ladder, 1,000 wallets, stages 0..5
    // ══════════════════════════════════════════════════════════════════

    function test_Stress1000_FullLadder_AllStages() public {
        console.log("================================================================");
        console.log("  1,000-WALLET AGGRESSIVE STRESS -- FULL LADDER, STAGES 0..5");
        console.log("================================================================");

        _runStage0();
        for (uint256 s = 1; s < 6; s++) _runHigherStage(s);

        _report();
        _assertConservation();
    }

    /// @dev Stage 0: all 1,000 wallets register under BFS placement.
    ///      Every single placement is checked against the ghost, not sampled.
    function _runStage0() internal {
        for (uint256 i = 0; i < WALLETS; i++) {
            address u = users[i];

            (address parent, BinaryMembershipV1.Side side) =
                membership.findOpenSlot(root, 0);
            assertTrue(parent != address(0), "stage0: BFS found no slot");

            uint256 expected = _ghostPlace(u, parent, 0);

            uint256 poolBefore = membership.totalPoolPaid();
            vm.prank(u);
            membership.register(root, parent, side);
            uint256 actual = membership.totalPoolPaid() - poolBefore;

            assertEq(actual, expected, "stage0: upline payout != ghost");
        }

        assertEq(membership.memberCount(), WALLETS + 1, "stage0: member count");
    }

    /// @dev Stages 1-5. users[0] is enrolled as the stage root by an operator;
    ///      everyone else pays and places by BFS beneath it.
    function _runHigherStage(uint256 s) internal {
        vm.prank(operator);
        membership.enrollStageRoot(users[0], s);
        ghostEnrolled[users[0]][s] = true;

        for (uint256 i = 1; i < JOINS[s]; i++) {
            address u = users[i];

            (address parent, BinaryMembershipV1.Side side) =
                membership.findOpenSlot(users[0], s);
            assertTrue(parent != address(0), "higher: BFS found no slot");

            uint256 expected = _ghostPlace(u, parent, s);

            uint256 poolBefore = membership.totalPoolPaid();
            vm.prank(u);
            membership.joinStage(s, parent, side);
            uint256 actual = membership.totalPoolPaid() - poolBefore;

            assertEq(actual, expected, "higher: upline payout != ghost");
        }
    }

    /// @dev Per-member cross-check: earnings and rollovers, contract vs ghost.
    function _report() internal {
        for (uint256 s = 0; s < 6; s++) {
            uint256 rolls;

            // The system root owns the stage-0 board and does nearly all the
            // cycling there, so it must be in the cross-check -- leaving it out
            // reports stage 0 as zero rollovers, which is a reporting artifact
            // rather than the truth.
            if (s == 0) {
                BinaryMembershipV1.StageMembership memory rm =
                    membership.getStageMembership(root, 0);
                assertEq(rm.stageEarnings, ghostEarnings[root][0], "root earnings != ghost");
                assertEq(rm.rolloverCount, ghostRollovers[root][0], "root rollovers != ghost");
                rolls += rm.rolloverCount;
                console.log("  root earnings (USD):", _usd(rm.stageEarnings));
            }

            for (uint256 i = 0; i < JOINS[s]; i++) {
                BinaryMembershipV1.StageMembership memory m =
                    membership.getStageMembership(users[i], s);

                assertEq(m.stageEarnings, ghostEarnings[users[i]][s],
                    "earnings diverge from ghost");
                assertEq(m.rolloverCount, ghostRollovers[users[i]][s],
                    "rollovers diverge from ghost");

                rolls += m.rolloverCount;
            }
            statRollovers[s] = rolls;

            console.log("--- stage", s);
            console.log("  placements :", statPlacements[s]);
            console.log("  pool paid  :", _usd(statPool[s]));
            console.log("  rollovers  :", rolls);
        }
    }

    function _assertConservation() internal view {
        assertEq(membership.totalPoolPaid(), ghostPool, "pool != ghost");
        assertEq(membership.totalTreasuryPaid(), ghostTreasury, "treasury != ghost");
        assertEq(
            membership.totalPoolPaid() + membership.totalTreasuryPaid(),
            ghostFees,
            "fees != pool + treasury"
        );
        assertEq(membership.pendingTreasury(), ghostTreasury, "pending != ghost");

        // Token conservation: everything seeded and paid in is still accounted for.
        assertEq(
            token.balanceOf(address(membership)),
            SEED + ghostFees - ghostPool,
            "contract balance drift"
        );

        console.log("================================================================");
        console.log("  fees collected :", _usd(ghostFees));
        console.log("  paid to members:", _usd(ghostPool));
        console.log("  treasury       :", _usd(ghostTreasury));
        console.log("  member share % :", (ghostPool * 100) / ghostFees);
        console.log("================================================================");
    }

    // ══════════════════════════════════════════════════════════════════
    //  Spillover: BFS must fill level by level, left before right
    // ══════════════════════════════════════════════════════════════════

    function test_Stress1000_SpilloverFillsBreadthFirst() public {
        // The first five placements build the plan sheet's shape:
        //          root
        //         /    \
        //       u0      u1        <- level 1 (direct)
        //      /  \    /
        //    u2   u3  u4          <- level 2 (spillover)
        //
        // Checked at five, because the sixth completes the board and rollover
        // immediately clears root's pointers — see the second half.
        for (uint256 i = 0; i < 5; i++) {
            (address p, BinaryMembershipV1.Side side) = membership.findOpenSlot(root, 0);
            vm.prank(users[i]);
            membership.register(root, p, side);
        }

        BinaryMembershipV1.StageMembership memory r = membership.getStageMembership(root, 0);
        assertEq(r.left, users[0], "root.left");
        assertEq(r.right, users[1], "root.right");
        assertEq(r.rolloverCount, 0, "rolled over too early");

        BinaryMembershipV1.StageMembership memory a = membership.getStageMembership(users[0], 0);
        assertEq(a.left, users[2], "u0.left");
        assertEq(a.right, users[3], "u0.right");

        BinaryMembershipV1.StageMembership memory b = membership.getStageMembership(users[1], 0);
        assertEq(b.left, users[4], "u1.left -- BFS must fill left before right");
        assertEq(b.right, address(0), "u1.right should still be open");

        // Sixth placement completes the 6-slot board and trips the rollover.
        (address p6, BinaryMembershipV1.Side s6) = membership.findOpenSlot(root, 0);
        assertEq(p6, users[1], "sixth slot should be u1.right");
        vm.prank(users[5]);
        membership.register(root, p6, s6);

        r = membership.getStageMembership(root, 0);
        assertEq(r.rolloverCount, 1, "board filled but did not roll over");
        assertEq(r.left, address(0), "rollover must clear root.left");
        assertEq(r.right, address(0), "rollover must clear root.right");

        // Board owner collected from all 6 positions: the plan's $30.
        assertEq(r.stageEarnings, 30 ether,
            "root should collect $30 from a full stage-0 board");

        // u1 keeps its own children -- only the node that filled up resets.
        assertEq(membership.getStageMembership(users[1], 0).right, users[5], "u1.right");
    }

    // ══════════════════════════════════════════════════════════════════
    //  Spillunder: members who recruited nobody must still earn
    // ══════════════════════════════════════════════════════════════════

    function test_Stress1000_SpillunderPaysNonRecruiters() public {
        // Everyone is sponsored by root, so nobody but root recruits anyone.
        for (uint256 i = 0; i < 300; i++) {
            (address p, BinaryMembershipV1.Side side) = membership.findOpenSlot(root, 0);
            vm.prank(users[i]);
            membership.register(root, p, side);
        }

        uint256 earners;
        uint256 spillunderPaid;
        for (uint256 i = 0; i < 300; i++) {
            uint256 e = membership.getStageMembership(users[i], 0).stageEarnings;
            if (e > 0) { earners++; spillunderPaid += e; }
        }

        assertGt(earners, 0, "spillunder produced no earners");
        console.log("non-recruiters who earned :", earners);
        console.log("paid to them (USD)        :", _usd(spillunderPaid));

        // Their earnings are real money out of the pool, not bookkeeping.
        assertLe(spillunderPaid, membership.totalPoolPaid(), "spillunder exceeds pool");
    }

    // ══════════════════════════════════════════════════════════════════
    //  Rollover: cycling must reopen slots and keep BFS shallow
    // ══════════════════════════════════════════════════════════════════

    function test_Stress1000_RolloverCyclesAndReopensSlots() public {
        for (uint256 i = 0; i < 600; i++) {
            (address p, BinaryMembershipV1.Side side) = membership.findOpenSlot(root, 0);
            _ghostPlace(users[i], p, 0);
            vm.prank(users[i]);
            membership.register(root, p, side);
        }

        // Root rolled over repeatedly and its ghost agrees.
        uint256 rollovers = membership.getStageMembership(root, 0).rolloverCount;
        assertEq(rollovers, ghostRollovers[root][0], "root rollovers != ghost");
        assertGt(rollovers, 0, "root never rolled over");

        // Each rollover pays a full board, so earnings track cycles exactly.
        assertEq(
            membership.getStageMembership(root, 0).stageEarnings,
            ghostEarnings[root][0],
            "root earnings != ghost"
        );

        // BFS stays shallow forever: the next slot is at most treeDepth down.
        (address next,) = membership.findOpenSlot(root, 0);
        uint256 depth;
        address cur = next;
        while (cur != root && cur != address(0)) {
            depth++;
            cur = membership.getStageMembership(cur, 0).parent;
            require(depth < 50, "BFS placement ran away from the root");
        }
        assertLe(depth, DEPTHS[0], "BFS drifted deeper than the board");
        console.log("root rollovers after 600 joins :", rollovers);
        console.log("next BFS slot depth            :", depth);
    }

    // ══════════════════════════════════════════════════════════════════
    //  Award cap holds under load
    // ══════════════════════════════════════════════════════════════════

    function test_Stress1000_AwardCapGateUnderLoad() public {
        for (uint256 i = 0; i < 300; i++) {
            (address p, BinaryMembershipV1.Side side) = membership.findOpenSlot(root, 0);
            vm.prank(users[i]);
            membership.register(root, p, side);
        }

        vm.prank(operator);
        membership.enrollStageRoot(users[0], 1);
        for (uint256 i = 1; i < 200; i++) {
            (address p, BinaryMembershipV1.Side side) = membership.findOpenSlot(users[0], 1);
            vm.prank(users[i]);
            membership.joinStage(1, p, side);
        }

        BinaryMembershipV1.StageMembership memory m =
            membership.getStageMembership(users[0], 1);
        assertGe(m.rolloverCount, AWARDS[1], "stage-1 root short of threshold");

        // Cap at 50%: an award above half of what they actually earned reverts.
        vm.prank(admin);
        membership.setAwardCapBps(5_000);

        uint256 cap = m.stageEarnings / 2;

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                BinaryMembershipV1.AwardExceedsCap.selector, cap, cap + 1
            )
        );
        membership.grantPhysicalAward(users[0], 1, cap + 1);

        // At the cap it settles.
        uint256 before = token.balanceOf(users[0]);
        vm.prank(operator);
        membership.grantPhysicalAward(users[0], 1, cap);
        assertEq(token.balanceOf(users[0]) - before, cap, "award not paid at cap");

        console.log("stage-1 root earnings (USD):", _usd(m.stageEarnings));
        console.log("award cap at 50%      (USD):", _usd(cap));
    }

    // ══════════════════════════════════════════════════════════════════
    //  Earnings distribution — who actually gets paid at scale
    // ══════════════════════════════════════════════════════════════════

    /// @notice Measures how stage-0 pool money is distributed across 1,000
    ///         members under the production placement strategy the README
    ///         prescribes: `findOpenSlot(root, stageId)` for everybody.
    ///
    ///  This asserts no spec rule. It records observed behaviour so the
    ///  economics are a decision rather than a surprise.
    function test_Stress1000_EarningsDistribution() public {
        for (uint256 i = 0; i < WALLETS; i++) {
            (address p, BinaryMembershipV1.Side side) = membership.findOpenSlot(root, 0);
            vm.prank(users[i]);
            membership.register(root, p, side);
        }

        uint256 pool = membership.totalPoolPaid();
        uint256 rootTook = membership.getStageMembership(root, 0).stageEarnings;

        uint256 earners;
        uint256 zeroEarners;
        uint256 maxMember;
        for (uint256 i = 0; i < WALLETS; i++) {
            uint256 e = membership.getStageMembership(users[i], 0).stageEarnings;
            if (e > 0) earners++; else zeroEarners++;
            if (e > maxMember) maxMember = e;
        }

        console.log("=============== STAGE-0 DISTRIBUTION, 1,000 MEMBERS ===========");
        console.log("  pool paid out      (USD):", _usd(pool));
        console.log("  system root took   (USD):", _usd(rootTook));
        console.log("  root share of pool   (%):", (rootTook * 100) / pool);
        console.log("  members who earned      :", earners);
        console.log("  members who earned $0   :", zeroEarners);
        console.log("  best non-root member(USD):", _usd(maxMember));
        console.log("==============================================================");

        // Conservation still holds regardless of how lopsided the split is.
        uint256 sum = rootTook;
        for (uint256 i = 0; i < WALLETS; i++) {
            sum += membership.getStageMembership(users[i], 0).stageEarnings;
        }
        assertEq(sum, pool, "per-member earnings must sum to the pool");
    }

    /// @notice Proves the cause of the lopsided split above: rollover clears
    ///         the board owner's child pointers, and BFS from the global root
    ///         then refills the root's own slots. The members it just detached
    ///         are unreachable by BFS forever, so they stop earning.
    function test_Stress1000_RolloverOrphansDetachMembersPermanently() public {
        for (uint256 i = 0; i < 6; i++) {
            (address p, BinaryMembershipV1.Side side) = membership.findOpenSlot(root, 0);
            vm.prank(users[i]);
            membership.register(root, p, side);
        }

        // Board full -> root rolled over and dropped u0 / u1.
        assertEq(membership.getStageMembership(root, 0).rolloverCount, 1, "no rollover");
        assertEq(membership.getStageMembership(root, 0).left, address(0), "left not cleared");

        // u0 still points up at root, but root no longer points down at u0.
        assertEq(membership.getStageMembership(users[0], 0).parent, root, "u0 lost its parent");

        // The next 100 placements all land back on the root's fresh slots or
        // their children -- u0 is never offered a slot again.
        uint256 u0Before = membership.getStageMembership(users[0], 0).stageEarnings;
        for (uint256 i = 6; i < 106; i++) {
            (address p, BinaryMembershipV1.Side side) = membership.findOpenSlot(root, 0);
            assertTrue(p != users[0], "orphan unexpectedly reachable by BFS");
            vm.prank(users[i]);
            membership.register(root, p, side);
        }

        assertEq(
            membership.getStageMembership(users[0], 0).stageEarnings,
            u0Before,
            "orphaned member should earn nothing further"
        );
        console.log("orphaned member final earnings (USD):", _usd(u0Before));
    }

    /// @notice Same 1,000 wallets, but placed from the SPONSOR's board instead
    ///         of the global root, falling back to the root only when the
    ///         sponsor's board is full. Recorded for comparison with
    ///         `test_Stress1000_EarningsDistribution`.
    function test_Stress1000_SponsorRootedPlacementDistribution() public {
        for (uint256 i = 0; i < WALLETS; i++) {
            // Spread sponsorship across the existing membership.
            address sponsor = i == 0 ? root : users[(i - 1) / 2];

            address p;
            BinaryMembershipV1.Side side;
            if (membership.getStageMembership(sponsor, 0).enrolled) {
                (p, side) = membership.findOpenSlot(sponsor, 0);
            }
            if (p == address(0)) {
                (p, side) = membership.findOpenSlot(root, 0);
                sponsor = root;
            }

            vm.prank(users[i]);
            membership.register(sponsor, p, side);
        }

        uint256 pool = membership.totalPoolPaid();
        uint256 rootTook = membership.getStageMembership(root, 0).stageEarnings;

        uint256 earners;
        uint256 maxMember;
        for (uint256 i = 0; i < WALLETS; i++) {
            uint256 e = membership.getStageMembership(users[i], 0).stageEarnings;
            if (e > 0) earners++;
            if (e > maxMember) maxMember = e;
        }

        console.log("========= STAGE-0 DISTRIBUTION, SPONSOR-ROOTED PLACEMENT ======");
        console.log("  pool paid out      (USD):", _usd(pool));
        console.log("  system root took   (USD):", _usd(rootTook));
        console.log("  root share of pool   (%):", (rootTook * 100) / pool);
        console.log("  members who earned      :", earners);
        console.log("  members who earned $0   :", WALLETS - earners);
        console.log("  best non-root member(USD):", _usd(maxMember));
        console.log("==============================================================");

        uint256 sum = rootTook;
        for (uint256 i = 0; i < WALLETS; i++) {
            sum += membership.getStageMembership(users[i], 0).stageEarnings;
        }
        assertEq(sum, pool, "per-member earnings must sum to the pool");
    }

    // ══════════════════════════════════════════════════════════════════
    //  Treasury withdrawal under load
    // ══════════════════════════════════════════════════════════════════

    function test_Stress1000_TreasuryWithdrawalUnderLoad() public {
        for (uint256 i = 0; i < 500; i++) {
            (address p, BinaryMembershipV1.Side side) = membership.findOpenSlot(root, 0);
            _ghostPlace(users[i], p, 0);
            vm.prank(users[i]);
            membership.register(root, p, side);
        }

        assertEq(membership.pendingTreasury(), ghostTreasury, "pending != ghost");

        uint256 half = ghostTreasury / 2;
        vm.prank(treasury);
        membership.withdrawTreasury(half);

        assertEq(token.balanceOf(treasury), half, "treasury wallet underpaid");
        assertEq(membership.pendingTreasury(), ghostTreasury - half, "pending after withdraw");

        // Over-withdrawal is refused.
        vm.prank(treasury);
        vm.expectRevert();
        membership.withdrawTreasury(ghostTreasury);

        console.log("treasury accrued (USD) :", _usd(ghostTreasury));
        console.log("withdrawn        (USD) :", _usd(half));
    }
}
