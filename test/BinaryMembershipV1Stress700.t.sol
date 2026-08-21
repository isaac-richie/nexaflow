// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice 700-wallet post-patch verification across user stages 1-4
///         (stageId 0-3), driven through the PRODUCTION placement path:
///         `findSponsorSlot` with the documented zero-parent fallback.
///
///  Every earlier stress run used root-anchored placement. This one exercises
///  the system the way it will actually be integrated, and re-verifies each
///  patch under that load:
///
///    DEFECT-1  every upline on the board is paid        -> ghost comparison
///    DEFECT-2  root position cannot be front-run        -> designatedRoot
///    DEFECT-3  board geometry is validated              -> config accepted
///    DEFECT-4  pause halts money in AND out             -> under live load
///    FINDING-2 award cap binds cumulatively             -> repeatable awards
///    root capture closed                                -> distribution
///
///  The ghost model is an independent reimplementation of the plan's rules.
///  Nothing is read back from the contract to build an expectation.
contract BinaryMembershipV1Stress700Test is Test {
    BinaryMembershipV1 public membership;
    MockERC20 public token;

    address admin     = address(0xAD);
    address treasury  = address(0x7EA5);
    address operator  = address(0x0B);
    address pauser    = address(0x9999);
    address outsider  = address(0xBAD);

    address root = address(0x1);
    address[] public users;

    uint256 constant WALLETS = 700;

    uint256[6] FEES   = [uint256(20 ether), 60 ether, 180 ether, 540 ether, 1620 ether, 4860 ether];
    uint256[6] NODES  = [uint256(5 ether), 10 ether, 25 ether, 80 ether, 250 ether, 800 ether];
    uint256[6] SLOTS  = [uint256(6), 14, 14, 14, 14, 14];
    uint256[6] DEPTHS = [uint256(2), 3, 3, 3, 3, 3];
    uint256[6] AWARDS = [uint256(0), 10, 10, 10, 10, 8];

    // stageId 0..3  ==  user-facing stages 1..4
    uint256[4] JOINS = [uint256(700), 350, 168, 84];

    uint256 constant SEED = 10_000_000 ether;
    uint256 constant FUND = 50_000 ether;

    // ── Ghost model ───────────────────────────────────────────────────
    mapping(address => mapping(uint256 => address)) gParent;
    mapping(address => mapping(uint256 => address)) gLeft;
    mapping(address => mapping(uint256 => address)) gRight;
    mapping(address => mapping(uint256 => uint256)) gSlots;
    mapping(address => mapping(uint256 => uint256)) gRollovers;
    mapping(address => mapping(uint256 => uint256)) gEarnings;

    uint256 gFees;
    uint256 gPool;
    uint256 gTreasury;

    // Per-stage stats
    uint256[4] sPlacements;
    uint256[4] sPool;
    uint256[4] sFees;
    uint256[4] sSpillunder;   // placements the sponsor did not personally recruit
    uint256[4] sDirect;       // placements landing directly on the sponsor

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
            address u = address(uint160(0x700000 + i));
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
    }

    function _usd(uint256 x) internal pure returns (uint256) { return x / 1 ether; }

    /// @dev Realistic referral topology. A perfect binary sponsor tree would
    ///      give every sponsor exactly two recruits — which fits their two
    ///      slots exactly, so spillover would never fire and the run would
    ///      prove nothing about it. Real programmes are lopsided: a handful of
    ///      recruiters bring in most people. Three leaders each sponsor ~230
    ///      members here, so their boards overflow continuously and every
    ///      placement past their second is genuine spillover — and they build
    ///      enough volume to exercise award-threshold logic under load.
    uint256 constant LEADERS = 3;

    function _sponsorOf(uint256 i) internal view returns (address) {
        if (i < LEADERS) return root;
        return users[i % LEADERS];
    }

    /// @dev A node's upward link is stale when its parent no longer claims it,
    ///      which is what rollover leaves behind. Both walks stop there, so a
    ///      detached branch cannot pay or credit an ancestor it has left.
    function _stale(address node, uint256 s) internal view returns (bool) {
        address p = gParent[node][s];
        if (p == address(0)) return false;
        return gLeft[p][s] != node && gRight[p][s] != node;
    }

    /// @dev Score a placement from the plan, not from the contract.
    function _ghost(
        address member,
        address parent,
        BinaryMembershipV1.Side side,
        uint256 s
    ) internal returns (uint256 payout) {
        // Attach first, matching the contract: the child pointer is written
        // before any upline is paid.
        gParent[member][s] = parent;
        if (side == BinaryMembershipV1.Side.Left) {
            gLeft[parent][s] = member;
        } else {
            gRight[parent][s] = member;
        }

        uint256 levels;
        address cur = parent;
        for (uint256 l = 0; l < DEPTHS[s] && cur != address(0); l++) {
            gEarnings[cur][s] += NODES[s];
            levels++;
            if (_stale(cur, s)) break;
            cur = gParent[cur][s];
        }
        payout = levels * NODES[s];

        cur = parent;
        for (uint256 l = 0; l < DEPTHS[s] && cur != address(0); l++) {
            gSlots[cur][s]++;
            if (gSlots[cur][s] >= SLOTS[s]) {
                gRollovers[cur][s]++;
                gSlots[cur][s] = 0;
                gLeft[cur][s] = address(0);
                gRight[cur][s] = address(0);
            }
            if (_stale(cur, s)) break;
            cur = gParent[cur][s];
        }

        gFees += FEES[s];
        gPool += payout;
        gTreasury += FEES[s] - payout;

        sPlacements[s]++;
        sPool[s] += payout;
        sFees[s] += FEES[s];
    }

    /// @dev Production placement, as a real frontend does it: one call.
    ///      `findPlacementSlot` absorbs both of `findSponsorSlot`'s failure
    ///      modes internally — the `SponsorChainExhausted` revert when the
    ///      upline has not reached this stage, and the zero parent when a board
    ///      is full — and resolves the stage anchor itself. The try/catch and
    ///      anchor bookkeeping this helper used to carry are gone.
    function _place(address sponsor, uint256 s)
        internal
        view
        returns (address parent, BinaryMembershipV1.Side side)
    {
        return membership.findPlacementSlot(sponsor, s);
    }

    // ══════════════════════════════════════════════════════════════════
    //  MAIN
    // ══════════════════════════════════════════════════════════════════

    function test_Stress700_PostPatch_Stages1to4() public {
        console.log("================================================================");
        console.log("  700-WALLET POST-PATCH RUN -- USER STAGES 1..4 (stageId 0..3)");
        console.log("  placement: findSponsorSlot + root fallback (production path)");
        console.log("================================================================");

        _runStage0();
        for (uint256 s = 1; s < 4; s++) _runHigherStage(s);

        _crossCheckEveryMember();
        _reportStages();
        _reportTreasury();
        _reportDistribution();
    }

    function _runStage0() internal {
        for (uint256 i = 0; i < WALLETS; i++) {
            address sponsor = _sponsorOf(i);
            (address parent, BinaryMembershipV1.Side side) = _place(sponsor, 0);
            assertTrue(parent != address(0), "stage0: no slot");

            if (parent == sponsor) sDirect[0]++; else sSpillunder[0]++;

            uint256 expected = _ghost(users[i], parent, side, 0);
            uint256 before = membership.totalPoolPaid();
            vm.prank(users[i]);
            membership.register(sponsor, parent, side);
            assertEq(membership.totalPoolPaid() - before, expected, "stage0 payout != ghost");
        }
        assertEq(membership.memberCount(), WALLETS + 1, "member count");
    }

    function _runHigherStage(uint256 s) internal {
        vm.prank(operator);
        membership.enrollStageRoot(users[0], s);

        for (uint256 i = 1; i < JOINS[s]; i++) {
            address sponsor = _sponsorOf(i);
            (address parent, BinaryMembershipV1.Side side) = _place(sponsor, s);
            assertTrue(parent != address(0), "higher: no slot");

            if (parent == sponsor) sDirect[s]++; else sSpillunder[s]++;

            uint256 expected = _ghost(users[i], parent, side, s);
            uint256 before = membership.totalPoolPaid();
            vm.prank(users[i]);
            membership.joinStage(s, parent, side);
            assertEq(membership.totalPoolPaid() - before, expected, "higher payout != ghost");
        }
    }

    /// @dev Earnings and rollovers checked on every member at every stage.
    function _crossCheckEveryMember() internal view {
        for (uint256 s = 0; s < 4; s++) {
            BinaryMembershipV1.StageMembership memory rm =
                membership.getStageMembership(root, s);
            assertEq(rm.stageEarnings, gEarnings[root][s], "root earnings != ghost");
            assertEq(rm.rolloverCount, gRollovers[root][s], "root rollovers != ghost");

            for (uint256 i = 0; i < JOINS[s]; i++) {
                BinaryMembershipV1.StageMembership memory m =
                    membership.getStageMembership(users[i], s);
                assertEq(m.stageEarnings, gEarnings[users[i]][s], "earnings != ghost");
                assertEq(m.rolloverCount, gRollovers[users[i]][s], "rollovers != ghost");
            }
        }
    }

    function _reportStages() internal view {
        console.log("");
        console.log("--- PER STAGE ------------------------------------------------");
        for (uint256 s = 0; s < 4; s++) {
            uint256 rolls;
            rolls += membership.getStageMembership(root, s).rolloverCount;
            for (uint256 i = 0; i < JOINS[s]; i++) {
                rolls += membership.getStageMembership(users[i], s).rolloverCount;
            }
            console.log("  user stage", s + 1);
            console.log("    placements     :", sPlacements[s]);
            console.log("    fees collected :", _usd(sFees[s]));
            console.log("    paid to members:", _usd(sPool[s]));
            console.log("    member share  %:", (sPool[s] * 100) / sFees[s]);
            console.log("    rollovers      :", rolls);
            console.log("    direct placings:", sDirect[s]);
            console.log("    spillover/under:", sSpillunder[s]);
        }
    }

    function _reportTreasury() internal view {
        console.log("");
        console.log("--- TREASURY -------------------------------------------------");
        console.log("  fees collected   :", _usd(gFees));
        console.log("  paid to members  :", _usd(gPool));
        console.log("  treasury earned  :", _usd(gTreasury));
        console.log("  treasury share  %:", (gTreasury * 100) / gFees);

        assertEq(membership.totalPoolPaid(), gPool, "pool != ghost");
        assertEq(membership.totalTreasuryPaid(), gTreasury, "treasury != ghost");
        assertEq(membership.pendingTreasury(), gTreasury, "pending != ghost");
        assertEq(
            membership.totalPoolPaid() + membership.totalTreasuryPaid(),
            gFees,
            "fees != pool + treasury"
        );
        assertEq(
            token.balanceOf(address(membership)),
            SEED + gFees - gPool,
            "contract balance drift"
        );
    }

    function _reportDistribution() internal view {
        uint256 pool = membership.totalPoolPaid();
        uint256 rootTook = membership.getStageMembership(root, 0).stageEarnings;

        uint256 earners;
        uint256 atFullBoard;
        uint256 best;
        for (uint256 i = 0; i < WALLETS; i++) {
            uint256 e = membership.getStageMembership(users[i], 0).stageEarnings;
            if (e > 0) earners++;
            if (e >= 30 ether) atFullBoard++;
            if (e > best) best = e;
        }

        console.log("");
        console.log("--- STAGE-1 DISTRIBUTION (root capture check) ----------------");
        console.log("  system root took (USD):", _usd(rootTook));
        console.log("  root share of pool  %:", (rootTook * 100) / pool);
        console.log("  members who earned   :", earners);
        console.log("  members at >= $30    :", atFullBoard);
        console.log("  best member     (USD):", _usd(best));
        console.log("==============================================================");

        // Root capture must stay closed under the production path.
        assertLt((rootTook * 100) / pool, 5, "root is capturing the pool again");
        assertGe(best, 30 ether, "no member reached the plan's $30 board");
    }

    // ══════════════════════════════════════════════════════════════════
    //  Patch verification under load
    // ══════════════════════════════════════════════════════════════════

    /// @notice DEFECT-2 still holds once the system is populated.
    function test_Stress700_RootStillCannotBeSeized() public {
        for (uint256 i = 0; i < 100; i++) {
            (address p, BinaryMembershipV1.Side side) = _place(_sponsorOf(i), 0);
            vm.prank(users[i]);
            membership.register(_sponsorOf(i), p, side);
        }

        // memberCount != 0 now, so the root branch is unreachable regardless,
        // but the guard is what makes that deterministic from block zero.
        assertEq(membership.designatedRoot(), root, "designatedRoot moved");

        vm.prank(outsider);
        vm.expectRevert();
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);
    }

    /// @notice FINDING-2 + repeatable awards: milestones advance one threshold
    ///         at a time and the cap binds on the CUMULATIVE total.
    function test_Stress700_RepeatableAwardsRespectCumulativeCap() public {
        for (uint256 i = 0; i < 400; i++) {
            (address p, BinaryMembershipV1.Side side) = _place(_sponsorOf(i), 0);
            vm.prank(users[i]);
            membership.register(_sponsorOf(i), p, side);
        }

        vm.prank(operator);
        membership.enrollStageRoot(users[0], 1);
        for (uint256 i = 1; i < 300; i++) {
            (address p, BinaryMembershipV1.Side side) = _place(_sponsorOf(i), 1);
            vm.prank(users[i]);
            membership.joinStage(1, p, side);
        }

        // Real rollover counts fell once phantom credits from detached branches
        // were removed, so the threshold is lowered here rather than inflating
        // the population. What this test is about is the cumulative cap, not
        // how many members it takes to reach a milestone.
        vm.prank(admin);
        membership.updateAwardThreshold(1, 3);

        (,, uint256 rollovers, uint256 milestone, bool eligible) =
            membership.getAwardInfo(users[0], 1);
        assertTrue(eligible, "stage-1 root should be award-eligible");
        assertEq(milestone, 3, "first milestone");

        uint256 earnings = membership.getStageMembership(users[0], 1).stageEarnings;

        // Cap at 50% of earnings, cumulative across every award.
        vm.prank(admin);
        membership.setAwardCapBps(5_000);
        uint256 capTotal = earnings / 2;

        // First award: half the ceiling.
        vm.prank(operator);
        membership.grantPhysicalAward(users[0], 1, capTotal / 2);

        (uint256 awarded,,, uint256 next,) = membership.getAwardInfo(users[0], 1);
        assertEq(awarded, capTotal / 2, "first award not recorded");
        assertEq(next, 6, "milestone should advance by one threshold");

        // Second award may only take the REMAINING headroom, not a fresh cap.
        vm.prank(operator);
        vm.expectRevert();
        membership.grantPhysicalAward(users[0], 1, capTotal);

        vm.prank(operator);
        membership.grantPhysicalAward(users[0], 1, capTotal - capTotal / 2);

        (awarded,,,,) = membership.getAwardInfo(users[0], 1);
        assertEq(awarded, capTotal, "cumulative total should sit exactly at the cap");

        // Ceiling reached: nothing more, however many rollovers remain.
        vm.prank(operator);
        vm.expectRevert();
        membership.grantPhysicalAward(users[0], 1, 1);

        console.log("rollovers          :", rollovers);
        console.log("stage-1 earnings   :", _usd(earnings));
        console.log("cumulative cap 50% :", _usd(capTotal));
        console.log("total awarded      :", _usd(awarded));
    }

    /// @notice DEFECT-4 under live load: pause stops joins, treasury and awards.
    function test_Stress700_PauseHaltsEverythingUnderLoad() public {
        for (uint256 i = 0; i < 200; i++) {
            (address p, BinaryMembershipV1.Side side) = _place(_sponsorOf(i), 0);
            vm.prank(users[i]);
            membership.register(_sponsorOf(i), p, side);
        }

        uint256 pending = membership.pendingTreasury();
        assertGt(pending, 0, "no treasury accrued");

        vm.prank(pauser);
        membership.pause();

        (address p2, BinaryMembershipV1.Side s2) = _place(_sponsorOf(200), 0);
        vm.prank(users[200]);
        vm.expectRevert();
        membership.register(_sponsorOf(200), p2, s2);

        vm.prank(treasury);
        vm.expectRevert();
        membership.withdrawTreasury(pending);

        vm.prank(pauser);
        membership.unpause();

        vm.prank(treasury);
        membership.withdrawTreasury(pending);
        assertEq(token.balanceOf(treasury), pending, "treasury not paid after unpause");

        console.log("treasury held then released (USD):", _usd(pending));
    }

    /// @notice Treasury withdrawal accounting under load, including refusal to
    ///         over-withdraw.
    function test_Stress700_TreasuryAccountingAndWithdrawal() public {
        for (uint256 i = 0; i < WALLETS; i++) {
            (address p, BinaryMembershipV1.Side side) = _place(_sponsorOf(i), 0);
            _ghost(users[i], p, side, 0);
            vm.prank(users[i]);
            membership.register(_sponsorOf(i), p, side);
        }

        assertEq(membership.pendingTreasury(), gTreasury, "pending != ghost");

        uint256 part = gTreasury / 3;
        vm.prank(treasury);
        membership.withdrawTreasury(part);
        assertEq(token.balanceOf(treasury), part, "partial withdrawal wrong");
        assertEq(membership.pendingTreasury(), gTreasury - part, "pending after withdraw");

        vm.prank(treasury);
        vm.expectRevert();
        membership.withdrawTreasury(gTreasury);

        vm.prank(treasury);
        membership.withdrawTreasury(gTreasury - part);
        assertEq(membership.pendingTreasury(), 0, "treasury should be drained");
        assertEq(token.balanceOf(treasury), gTreasury, "treasury total wrong");

        console.log("stage-1 fees collected (USD):", _usd(gFees));
        console.log("stage-1 to members     (USD):", _usd(gPool));
        console.log("stage-1 treasury       (USD):", _usd(gTreasury));
    }
}
