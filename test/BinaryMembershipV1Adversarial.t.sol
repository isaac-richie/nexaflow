// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Adversarial placement stress.
///
///  The frontend places via findOpenSlot (BFS from the stage root), which keeps
///  trees shallow. Nothing in the contract ENFORCES that — anyone can call
///  register/joinStage directly with a hand-picked parent and build shapes BFS
///  never makes. These tests build those shapes deliberately.
///
///  Payouts and slot propagation are capped at `treeDepth`, so their cost is
///  constant. The optional liveness guard validates the complete parent path
///  under a separate hard cap, so its cost can grow only to that fixed ceiling.
contract BinaryMembershipV1AdversarialTest is Test {
    BinaryMembershipV1 public membership;
    MockERC20 public token;

    address admin = address(0xAD);
    address treasuryWallet = address(0x7EA5);
    address operator = address(0x0B);
    address pauser = address(0x9999);

    address root = address(0x1);
    address[] public users;

    uint256 constant WALLETS = 300;
    uint256 constant FEE_0 = 20 ether;
    uint256 constant NODE_0 = 5 ether;
    uint256 constant SLOTS_0 = 6;
    uint256 constant DEPTH_0 = 2;
    uint256 constant CONTRACT_SEED = 5_000_000 ether;

    uint256 public ghostFeesPulled;
    uint256 public ghostPoolPaid;

    function setUp() public {
        token = new MockERC20("FAKEUSD", "FUSD", 0);

        vm.startPrank(admin);
        membership = new BinaryMembershipV1(
            IERC20(address(token)), treasuryWallet, admin, 0, root
        );
        membership.grantRole(membership.OPERATOR_ROLE(), operator);
        membership.grantRole(membership.TREASURY_ROLE(), treasuryWallet);
        membership.grantRole(membership.PAUSER_ROLE(), pauser);

        membership.configureStages(
            [uint256(20 ether), 60 ether, 180 ether, 540 ether, 1620 ether, 4860 ether],
            [uint256(5 ether), 10 ether, 25 ether, 80 ether, 250 ether, 800 ether],
            [uint256(6), 14, 14, 14, 14, 14],
            [uint256(2), 3, 3, 3, 3, 3],
            [uint256(0), 10, 10, 10, 10, 8]
        );
        vm.stopPrank();

        for (uint256 i = 0; i < WALLETS; i++) {
            address u = address(uint160(0x200000 + i));
            users.push(u);
            token.mint(u, 50_000 ether);
            vm.prank(u);
            token.approve(address(membership), type(uint256).max);
        }

        token.mint(address(membership), CONTRACT_SEED);

        vm.prank(root);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);
    }

    // ══════════════════════════════════════════════════════════════════
    //  1. DEEP CHAIN — gas and payout must stay flat
    // ══════════════════════════════════════════════════════════════════

    /// @dev Before the board-depth cap, `_propagateSlotFilled` walked the whole
    ///      ancestor chain and gas grew ~3,708 per level (383k at depth 1 →
    ///      1,347k at depth 250). Both the payout walk and the propagation walk
    ///      are now capped at `treeDepth`, so cost must be flat.
    function test_Adversarial_DeepChain_GasStaysFlat() public {
        uint256 depth = 250;
        address prev = root;
        uint256 gasAt50;
        uint256 gasAt250;

        for (uint256 i = 0; i < depth; i++) {
            uint256 due = _expectedPayout(prev, 0);

            uint256 g0 = gasleft();
            vm.prank(users[i]);
            membership.register(root, prev, BinaryMembershipV1.Side.Left);
            uint256 used = g0 - gasleft();

            ghostFeesPulled += FEE_0;
            ghostPoolPaid += due;

            if (i == 49) gasAt50 = used;
            if (i == depth - 1) gasAt250 = used;

            if (i == 0 || i == 49 || i == 99 || i == 199 || i == depth - 1) {
                console.log("  depth %d -> gas %d", i + 1, used);
            }

            prev = users[i];
        }

        console.log("  gas at depth 50:  %d", gasAt50);
        console.log("  gas at depth 250: %d", gasAt250);

        // Flat, not linear. A 5x depth increase must not meaningfully move gas.
        assertLt(
            gasAt250,
            (gasAt50 * 3) / 2,
            "REGRESSION: gas still grows with tree depth - board cap is not holding"
        );

        _assertConservation();
    }

    /// @dev The payout side of the same cap: however deep the chain, a single
    ///      join must never pay more than `treeDepth * nodeReward`.
    function test_Adversarial_DeepChain_PayoutStaysBounded() public {
        uint256 cap = DEPTH_0 * NODE_0;
        address prev = root;

        for (uint256 i = 0; i < 120; i++) {
            uint256 poolBefore = membership.totalPoolPaid();
            uint256 due = _expectedPayout(prev, 0);

            vm.prank(users[i]);
            membership.register(root, prev, BinaryMembershipV1.Side.Left);

            uint256 actual = membership.totalPoolPaid() - poolBefore;

            assertEq(actual, due, "payout diverged from independent expectation");
            assertLe(actual, cap, "PAYOUT UNBOUNDED: a join paid more than treeDepth uplines");
            assertLt(actual, FEE_0, "INSOLVENT: a join paid out more than it collected");

            ghostFeesPulled += FEE_0;
            ghostPoolPaid += due;
            prev = users[i];
        }

        console.log("  max payout per join: %d FUSD (cap %d)", cap / 1 ether, cap / 1 ether);
        _assertConservation();
    }

    /// @dev The guard must inspect the whole path to close deep-detachment
    ///      bypasses, but must still have a hard gas bound. Paths through the
    ///      configured maximum are accepted; a parent beyond it is rejected.
    function test_Adversarial_CycleGuard_IsBoundedAndRejectsOverdeepPaths() public {
        vm.prank(admin);
        membership.setCycleGuardEnabled(true);

        address prev = root;
        uint256 gasAt20;
        uint256 gasAt150;
        uint256 gasAt257;

        // A child at depth MAX_LIVE_PATH + 1 can be placed under a parent whose
        // own path is exactly MAX_LIVE_PATH links. It cannot itself be used as
        // a guarded parent, which is the boundary checked below.
        for (uint256 i = 0; i <= membership.MAX_LIVE_PATH(); i++) {
            uint256 due = _expectedPayout(prev, 0);

            uint256 g0 = gasleft();
            vm.prank(users[i]);
            membership.register(root, prev, BinaryMembershipV1.Side.Left);
            uint256 used = g0 - gasleft();

            ghostFeesPulled += FEE_0;
            ghostPoolPaid += due;

            if (i == 19) gasAt20 = used;
            if (i == 149) gasAt150 = used;
            if (i == membership.MAX_LIVE_PATH()) gasAt257 = used;
            prev = users[i];
        }

        console.log("  guard ON, gas at depth 20:  %d", gasAt20);
        console.log("  guard ON, gas at depth 150: %d", gasAt150);
        console.log("  guard ON, gas at boundary:  %d", gasAt257);

        // The full validation is linear by design but cannot exceed the fixed
        // 256-link ceiling, keeping it comfortably below a transaction limit.
        assertLt(
            gasAt257,
            5_000_000,
            "cycle guard exceeds its bounded gas budget"
        );

        uint256 limit = membership.MAX_LIVE_PATH();
        address overdeepChild = users[limit + 1];
        vm.expectRevert(
            abi.encodeWithSelector(
                BinaryMembershipV1.ParentPathTooDeep.selector, prev, uint256(0)
            )
        );
        vm.prank(overdeepChild);
        membership.register(root, prev, BinaryMembershipV1.Side.Left);

        _assertConservation();
    }

    // ══════════════════════════════════════════════════════════════════
    //  2. PSEUDO-RANDOM MANUAL PLACEMENT
    // ══════════════════════════════════════════════════════════════════

    function test_Adversarial_RandomPlacement_Conservation() public {
        address[] memory placed = new address[](WALLETS + 1);
        uint256 placedLen;
        placed[placedLen++] = root;

        uint256 successful;

        for (uint256 i = 0; i < WALLETS; i++) {
            uint256 seed = uint256(keccak256(abi.encode(i, block.timestamp)));

            (address parent, BinaryMembershipV1.Side side) =
                _findManualSlot(placed, placedLen, seed);
            if (parent == address(0)) continue;

            uint256 pBefore = token.balanceOf(parent);
            uint256 poolBefore = membership.totalPoolPaid();
            uint256 due = _expectedPayout(parent, 0);

            vm.prank(users[i]);
            membership.register(root, parent, side);

            assertEq(
                token.balanceOf(parent) - pBefore,
                NODE_0,
                "random placement: direct parent underpaid"
            );
            assertEq(
                membership.totalPoolPaid() - poolBefore,
                due,
                "random placement: board total wrong"
            );

            ghostFeesPulled += FEE_0;
            ghostPoolPaid += due;
            placed[placedLen++] = users[i];
            successful++;
        }

        console.log("  placed: %d", successful);
        assertGt(successful, 250, "manual placement mostly failed - test is weak");

        _assertConservation();
        _assertNoSlotCounterOverflow(placed, placedLen);
    }

    // ══════════════════════════════════════════════════════════════════
    //  3. PLACEMENT UNDER ROLLOVER-ORPHANED NODES
    // ══════════════════════════════════════════════════════════════════

    function test_Adversarial_OrphanedPlacement_AccountingHolds() public {
        for (uint256 i = 0; i < 12; i++) {
            (address p, BinaryMembershipV1.Side s) = membership.findOpenSlot(root, 0);
            ghostPoolPaid += _expectedPayout(p, 0);
            vm.prank(users[i]);
            membership.register(root, p, s);
            ghostFeesPulled += FEE_0;
        }

        (,,, uint256 rolls,,) = membership.getTreeInfo(root, 0);
        assertEq(rolls, 2, "expected 2 rollovers");

        uint256 placedOnOrphans;
        for (uint256 i = 12; i < 40; i++) {
            address orphan = users[(i % 4) + 2];
            BinaryMembershipV1.Side side = (i % 2 == 0)
                ? BinaryMembershipV1.Side.Left
                : BinaryMembershipV1.Side.Right;

            if (!membership.isSlotAvailable(orphan, 0, side)) continue;

            uint256 pBefore = token.balanceOf(orphan);
            uint256 due = _expectedPayout(orphan, 0);

            vm.prank(users[i]);
            membership.register(root, orphan, side);

            assertEq(
                token.balanceOf(orphan) - pBefore,
                NODE_0,
                "orphan placement: direct parent underpaid"
            );

            ghostFeesPulled += FEE_0;
            ghostPoolPaid += due;
            placedOnOrphans++;
        }

        console.log("  placed on orphaned nodes: %d", placedOnOrphans);
        assertGt(placedOnOrphans, 0, "no orphan placements happened");

        _assertConservation();
    }

    // ══════════════════════════════════════════════════════════════════
    //  4. MANUAL PLACEMENT ACROSS STAGES 0-4
    // ══════════════════════════════════════════════════════════════════

    function test_Adversarial_ManualPlacement_AllStages() public {
        uint256[5] memory nodes =
            [uint256(5 ether), 10 ether, 25 ether, 80 ether, 250 ether];
        uint256[5] memory fees =
            [uint256(20 ether), 60 ether, 180 ether, 540 ether, 1620 ether];

        // Stage 0: chain of 60
        address prev = root;
        for (uint256 i = 0; i < 60; i++) {
            uint256 due = _expectedPayout(prev, 0);
            vm.prank(users[i]);
            membership.register(root, prev, BinaryMembershipV1.Side.Left);
            ghostFeesPulled += fees[0];
            ghostPoolPaid += due;
            prev = users[i];
        }

        // Stages 1..4: manual chains off each stage root
        for (uint256 s = 1; s <= 4; s++) {
            vm.prank(operator);
            membership.enrollStageRoot(root, s);

            address p = root;
            for (uint256 i = 0; i < 20; i++) {
                BinaryMembershipV1.Side side =
                    membership.isSlotAvailable(p, s, BinaryMembershipV1.Side.Left)
                        ? BinaryMembershipV1.Side.Left
                        : BinaryMembershipV1.Side.Right;

                if (!membership.isSlotAvailable(p, s, side)) break;

                uint256 pBefore = token.balanceOf(p);
                uint256 due = _expectedPayout(p, s);

                vm.prank(users[i]);
                membership.joinStage(s, p, side);

                assertEq(
                    token.balanceOf(p) - pBefore,
                    nodes[s],
                    "multi-stage manual: direct parent underpaid"
                );

                ghostFeesPulled += fees[s];
                ghostPoolPaid += due;
                p = users[i];
            }
        }

        _assertConservation();
    }

    // ══════════════════════════════════════════════════════════════════
    //  5. CYCLE GUARD PRESERVES DETACHED BOARD BOUNDARIES
    // ══════════════════════════════════════════════════════════════════

    function test_Adversarial_CycleGuard_AllowsDetachedBoardWithoutRootCredit() public {
        vm.prank(admin);
        membership.setCycleGuardEnabled(true);

        for (uint256 i = 0; i < 12; i++) {
            (address p, BinaryMembershipV1.Side s) = membership.findOpenSlot(root, 0);
            ghostPoolPaid += _expectedPayout(p, 0);
            vm.prank(users[i]);
            membership.register(root, p, s);
            ghostFeesPulled += FEE_0;
        }

        BinaryMembershipV1.StageMembership memory rootBefore =
            membership.getStageMembership(root, 0);

        // users[0]'s first board is detached after root rolls. Continue
        // placing there through the public finder; every placement must work,
        // and none may travel back across the stale edge into root.
        for (uint256 i; i < 6; i++) {
            (address p, BinaryMembershipV1.Side s) =
                membership.findPlacementSlot(users[0], 0);
            uint256 due = _expectedPayout(p, 0);
            vm.prank(users[102 + i]);
            membership.register(root, p, s);
            ghostFeesPulled += FEE_0;
            ghostPoolPaid += due;
        }

        BinaryMembershipV1.StageMembership memory rootAfter =
            membership.getStageMembership(root, 0);
        assertEq(rootAfter.slotsFilledBelow, rootBefore.slotsFilledBelow, "detached chain credited root");
        assertEq(rootAfter.rolloverCount, rootBefore.rolloverCount, "detached chain rolled root");

        _assertConservation();
    }

    // ══════════════════════════════════════════════════════════════════
    //  helpers
    // ══════════════════════════════════════════════════════════════════

    /// @dev Independent expectation: walks the tree to count payable uplines,
    ///      capped at board depth. Does not consult the payment code.
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

            // The walk stops at a detached link, so the expectation must too.
            // Rollover clears a parent's child pointers without clearing the
            // child's `parent`, leaving a one-way link; paying through it would
            // credit an ancestor this placement is no longer beneath.
            BinaryMembershipV1.StageMembership memory m =
                membership.getStageMembership(cur, stageId);
            address par = m.parent;
            if (par == address(0)) break;

            BinaryMembershipV1.StageMembership memory pm =
                membership.getStageMembership(par, stageId);
            if (pm.left != cur && pm.right != cur) break;

            cur = par;
        }
        return count * c.nodeReward;
    }

    function _findManualSlot(
        address[] memory pool,
        uint256 len,
        uint256 seed
    ) internal view returns (address parent, BinaryMembershipV1.Side side) {
        uint256 start = seed % len;
        for (uint256 k = 0; k < len; k++) {
            address cand = pool[(start + k) % len];
            if (membership.isSlotAvailable(cand, 0, BinaryMembershipV1.Side.Left)) {
                return (cand, BinaryMembershipV1.Side.Left);
            }
            if (membership.isSlotAvailable(cand, 0, BinaryMembershipV1.Side.Right)) {
                return (cand, BinaryMembershipV1.Side.Right);
            }
        }
        return (address(0), BinaryMembershipV1.Side.None);
    }

    function _assertConservation() internal view {
        assertEq(
            membership.totalPoolPaid(),
            ghostPoolPaid,
            "pool paid diverged from ghost"
        );
        assertEq(
            membership.totalPoolPaid() + membership.totalTreasuryPaid(),
            ghostFeesPulled,
            "fee conservation violated"
        );
        assertEq(
            token.balanceOf(address(membership)),
            CONTRACT_SEED + ghostFeesPulled - ghostPoolPaid,
            "contract balance conservation violated"
        );
        assertGe(
            token.balanceOf(address(membership)),
            membership.pendingTreasury(),
            "insolvent"
        );
    }

    function _assertNoSlotCounterOverflow(
        address[] memory pool,
        uint256 len
    ) internal view {
        for (uint256 i = 0; i < len; i++) {
            (,, uint256 slots,,,) = membership.getTreeInfo(pool[i], 0);
            assertLt(slots, SLOTS_0, "slotsFilledBelow reached treeSlots without reset");
        }
    }
}
