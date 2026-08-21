// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice 300-wallet full-system stress test across stages 0-4.
///         Verifies upline payment, spillover, spillunder, rollover,
///         treasury accounting, admin roles, and global token conservation.
///
///  Assertions are derived independently from the spec, NOT read back from
///  the contract, so a logic bug shows up as a failure rather than being
///  silently confirmed.
contract BinaryMembershipV1Stress300Test is Test {
    BinaryMembershipV1 public membership;
    MockERC20 public token;

    address admin = address(0xAD);
    address treasuryWallet = address(0x7EA5);
    address operator = address(0x0B);
    address pauser = address(0x9999);
    address outsider = address(0xBAD);

    address root = address(0x1);
    address[] public users;

    uint256 constant WALLETS = 300;

    // Stage spec (stageId => value)
    uint256[5] FEES = [uint256(20 ether), 60 ether, 180 ether, 540 ether, 1620 ether];
    uint256[5] NODES = [uint256(5 ether), 10 ether, 25 ether, 80 ether, 250 ether];
    uint256[5] SLOTS = [uint256(6), 14, 14, 14, 14];

    // How many members join each stage
    uint256[5] JOINS = [uint256(300), 140, 70, 42, 28];

    uint256 constant CONTRACT_SEED = 5_000_000 ether;

    // Ghost accounting (independent of contract state)
    uint256 public ghostFeesPulled;
    uint256 public ghostPoolPaid;
    uint256 public ghostTreasuryWithdrawn;
    uint256 public ghostAwardsPaid;

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
            [FEES[0], FEES[1], FEES[2], FEES[3], FEES[4], 4860 ether],
            [NODES[0], NODES[1], NODES[2], NODES[3], NODES[4], 800 ether],
            [SLOTS[0], SLOTS[1], SLOTS[2], SLOTS[3], SLOTS[4], 14],
            [uint256(2), 3, 3, 3, 3, 3],
            [uint256(0), 10, 10, 10, 10, 8]
        );
        vm.stopPrank();

        // 300 wallets, funded well past the 0-4 ladder cost ($2,420)
        for (uint256 i = 0; i < WALLETS; i++) {
            address u = address(uint160(0x100000 + i));
            users.push(u);
            token.mint(u, 50_000 ether);
            vm.prank(u);
            token.approve(address(membership), type(uint256).max);
        }

        token.mint(root, 50_000 ether);
        vm.prank(root);
        token.approve(address(membership), type(uint256).max);

        // Seed contract so physical awards have backing
        token.mint(address(membership), CONTRACT_SEED);

        vm.prank(root);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);
    }

    /// @dev Independent expectation: walk the tree to count how many uplines
    ///      a placement under `parent` should pay, capped at the board depth.
    ///      Deliberately does not consult the payment code.
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

    // ══════════════════════════════════════════════════════════════════
    //  MAIN: full system run
    // ══════════════════════════════════════════════════════════════════

    function test_Stress300_Stages0to4_FullSystem() public {
        console.log("===========================================================");
        console.log("  300-WALLET FULL SYSTEM STRESS -- STAGES 0..4");
        console.log("===========================================================");

        _phase_stage0();
        _phase_higherStages();
        _phase_spillunderProof();
        _phase_awards();
        _phase_treasury();
        _phase_globalConservation();

        console.log("");
        console.log("ALL SYSTEM ASSERTIONS PASSED");
    }

    // ── Phase 1: stage 0, all 300 wallets ────────────────────────────

    function _phase_stage0() internal {
        console.log("");
        console.log("--- PHASE 1: 300 WALLETS -> STAGE 0 ($20) ---");

        for (uint256 i = 0; i < JOINS[0]; i++) {
            (address parent, BinaryMembershipV1.Side side) =
                membership.findOpenSlot(root, 0);
            assertTrue(parent != address(0), "BFS found no slot at stage 0");

            uint256 pBefore = token.balanceOf(parent);
            uint256 uBefore = token.balanceOf(users[i]);
            uint256 poolBefore = membership.totalPoolPaid();
            uint256 due = _expectedPayout(parent, 0);

            vm.prank(users[i]);
            membership.register(root, parent, side);

            // Direct parent still gets exactly one nodeReward
            assertEq(
                token.balanceOf(parent) - pBefore,
                NODES[0],
                "stage0: direct parent did not receive exact nodeReward"
            );
            // And the whole board above it gets paid too
            assertEq(
                membership.totalPoolPaid() - poolBefore,
                due,
                "stage0: board uplines not paid the expected total"
            );
            // Member paid EXACTLY fee
            assertEq(
                uBefore - token.balanceOf(users[i]),
                FEES[0],
                "stage0: member did not pay exact fee"
            );

            ghostFeesPulled += FEES[0];
            ghostPoolPaid += due;
        }

        // Rollover math derived from spec, not read from contract
        uint256 expectedRollovers = JOINS[0] / SLOTS[0]; // 300/6 = 50
        (,,, uint256 rollovers,,) = membership.getTreeInfo(root, 0);
        assertEq(rollovers, expectedRollovers, "stage0 rollover count wrong");

        (,, uint256 slotsLeft,,,) = membership.getTreeInfo(root, 0);
        assertEq(slotsLeft, JOINS[0] % SLOTS[0], "stage0 leftover slots wrong");

        assertEq(membership.memberCount(), WALLETS + 1, "member count wrong");

        console.log("  Registered:      %d", JOINS[0]);
        console.log("  Root rollovers:  %d (expected %d)", rollovers, expectedRollovers);
        console.log("  Pool paid:       %d FUSD", ghostPoolPaid / 1 ether);
    }

    // ── Phase 2: stages 1..4 ─────────────────────────────────────────

    function _phase_higherStages() internal {
        for (uint256 s = 1; s <= 4; s++) {
            console.log("");
            console.log("--- PHASE 2.%d: STAGE %d ---", s, s);

            vm.prank(operator);
            membership.enrollStageRoot(root, s);

            uint256 n = JOINS[s];
            uint256 poolBefore = ghostPoolPaid;

            for (uint256 i = 0; i < n; i++) {
                (address parent, BinaryMembershipV1.Side side) =
                    membership.findOpenSlot(root, s);
                assertTrue(parent != address(0), "BFS found no slot");

                uint256 pBefore = token.balanceOf(parent);
                uint256 poolBefore2 = membership.totalPoolPaid();
                uint256 due = _expectedPayout(parent, s);

                vm.prank(users[i]);
                membership.joinStage(s, parent, side);

                assertEq(
                    token.balanceOf(parent) - pBefore,
                    NODES[s],
                    "higher stage: direct parent did not receive exact nodeReward"
                );
                assertEq(
                    membership.totalPoolPaid() - poolBefore2,
                    due,
                    "higher stage: board uplines not paid the expected total"
                );

                ghostFeesPulled += FEES[s];
                ghostPoolPaid += due;
            }

            uint256 expectedRollovers = n / SLOTS[s];
            (,,, uint256 rollovers,,) = membership.getTreeInfo(root, s);
            assertEq(rollovers, expectedRollovers, "higher stage rollover count wrong");

            console.log("  Joined:          %d", n);
            console.log("  Root rollovers:  %d (expected %d)", rollovers, expectedRollovers);
            console.log("  Pool paid here:  %d FUSD", (ghostPoolPaid - poolBefore) / 1 ether);
        }
    }

    // ── Phase 3: spillunder actually pays non-recruiters ─────────────

    function _phase_spillunderProof() internal {
        console.log("");
        console.log("--- PHASE 3: SPILLOVER / SPILLUNDER PROOF ---");

        // Every non-root member was sponsored by root and recruited NOBODY.
        // So any earnings they hold are pure spillunder.
        uint256 nonRootEarnings;
        uint256 earnersWithZeroRecruits;

        for (uint256 i = 0; i < WALLETS; i++) {
            BinaryMembershipV1.Member memory m = membership.getMember(users[i]);
            if (m.totalEarned > 0) {
                // sponsor must be root => they recruited no one themselves
                assertEq(m.sponsor, root, "unexpected sponsor");
                nonRootEarnings += m.totalEarned;
                earnersWithZeroRecruits++;
            }
        }

        assertGt(
            earnersWithZeroRecruits,
            0,
            "SPILLUNDER BROKEN: nobody earned without recruiting"
        );

        // Root earns only from its own 2 direct slots per cycle.
        // Everything else in the pool went to downline via spillunder.
        BinaryMembershipV1.Member memory rootM = membership.getMember(root);
        assertEq(
            rootM.totalEarned + nonRootEarnings,
            ghostPoolPaid,
            "pool split between root and downline does not reconcile"
        );
        assertGt(nonRootEarnings, 0, "no spillunder earnings distributed");

        console.log("  Members earning w/o recruiting: %d", earnersWithZeroRecruits);
        console.log("  Root earned:        %d FUSD", rootM.totalEarned / 1 ether);
        console.log("  Spillunder earned:  %d FUSD", nonRootEarnings / 1 ether);
    }

    // ── Phase 4: physical awards ─────────────────────────────────────

    function _phase_awards() internal {
        console.log("");
        console.log("--- PHASE 4: PHYSICAL AWARDS ---");

        // Stage 0 has rolloversForAward == 0 => award must be rejected
        vm.expectRevert(
            abi.encodeWithSelector(BinaryMembershipV1.InvalidStage.selector, uint256(0))
        );
        vm.prank(operator);
        membership.grantPhysicalAward(root, 0, 1 ether);

        // Stage 1: root has 140/14 = 10 rollovers, exactly the new threshold.
        (,,,,, uint256 rootEarnings1) = membership.getTreeInfo(root, 1);
        uint256 maxAward = (rootEarnings1 * membership.awardCapBps()) / 10_000;

        uint256 before = token.balanceOf(root);
        vm.prank(operator);
        membership.grantPhysicalAward(root, 1, maxAward);
        ghostAwardsPaid += maxAward;
        assertEq(token.balanceOf(root) - before, maxAward, "award not transferred");

        // A repeat award requires rollover 20 — only 10 are complete.
        (,,,, uint256 lastAwarded,) = membership.getTreeInfo(root, 1);
        (,,, uint256 rootRoll,,) = membership.getTreeInfo(root, 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                BinaryMembershipV1.RolloversNotMet.selector, lastAwarded + 10, rootRoll
            )
        );
        vm.prank(operator);
        membership.grantPhysicalAward(root, 1, 1);

        // A member who has NOT met the threshold must be rejected
        (,,, uint256 uRoll,,) = membership.getTreeInfo(users[0], 1);
        if (uRoll < 10) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    BinaryMembershipV1.RolloversNotMet.selector, uint256(10), uRoll
                )
            );
            vm.prank(operator);
            membership.grantPhysicalAward(users[0], 1, maxAward / 2);
        }

        // Non-operator must be rejected
        vm.expectRevert();
        vm.prank(outsider);
        membership.grantPhysicalAward(root, 2, maxAward / 2);

        console.log("  Award granted:   %d FUSD", maxAward / 1 ether);
        console.log("  Award records:   %d", membership.getAwardRecordCount());
    }

    // ── Phase 5: treasury ────────────────────────────────────────────

    function _phase_treasury() internal {
        console.log("");
        console.log("--- PHASE 5: TREASURY ---");

        uint256 expectedTreasury = ghostFeesPulled - ghostPoolPaid;
        assertEq(
            membership.totalTreasuryPaid(),
            expectedTreasury,
            "treasury accrual does not match spec"
        );

        // Awards are paid out of treasury funds and now reduce the liability
        // as well as the balance. Before that fix `pendingTreasury` kept
        // claiming money the contract had already handed out, and with no
        // pre-seed the treasury could not withdraw what its own books promised.
        assertEq(
            membership.pendingTreasury(),
            expectedTreasury - ghostAwardsPaid,
            "pending treasury should fall by awards granted"
        );
        assertEq(
            membership.totalAwardsPaid(),
            ghostAwardsPaid,
            "award total not tracked"
        );

        // Over-withdraw must revert. The ceiling is what remains AFTER awards,
        // not the gross accrual, since awards are drawn from the same pot.
        uint256 available = membership.pendingTreasury();
        vm.expectRevert(
            abi.encodeWithSelector(
                BinaryMembershipV1.InsufficientPendingTreasury.selector,
                available,
                available + 1
            )
        );
        vm.prank(treasuryWallet);
        membership.withdrawTreasury(available + 1);

        // Non-treasury role must revert
        vm.expectRevert();
        vm.prank(outsider);
        membership.withdrawTreasury(1 ether);

        // Partial then full drain
        uint256 half = available / 2;
        uint256 walletBefore = token.balanceOf(treasuryWallet);

        vm.prank(treasuryWallet);
        membership.withdrawTreasury(half);
        ghostTreasuryWithdrawn += half;

        uint256 rest = membership.pendingTreasury();
        vm.prank(treasuryWallet);
        membership.withdrawTreasury(rest);
        ghostTreasuryWithdrawn += rest;

        assertEq(
            token.balanceOf(treasuryWallet) - walletBefore,
            available,
            "treasury wallet did not receive full amount"
        );
        assertEq(membership.pendingTreasury(), 0, "pending not zero after drain");

        console.log("  Treasury accrued: %d FUSD", expectedTreasury / 1 ether);
        console.log("  Wallet balance:   %d FUSD", token.balanceOf(treasuryWallet) / 1 ether);
    }

    // ── Phase 6: global token conservation ───────────────────────────

    function _phase_globalConservation() internal view {
        console.log("");
        console.log("--- PHASE 6: GLOBAL CONSERVATION ---");

        // Contract balance must equal every token in minus every token out.
        uint256 expected = CONTRACT_SEED
            + ghostFeesPulled
            - ghostPoolPaid
            - ghostTreasuryWithdrawn
            - ghostAwardsPaid;

        assertEq(
            token.balanceOf(address(membership)),
            expected,
            "GLOBAL CONSERVATION VIOLATED"
        );

        // Contract-side accounting must agree with our independent ghosts
        assertEq(membership.totalPoolPaid(), ghostPoolPaid, "totalPoolPaid mismatch");
        assertEq(
            membership.totalPoolPaid() + membership.totalTreasuryPaid(),
            ghostFeesPulled,
            "fee conservation mismatch"
        );

        console.log("  Fees pulled:      %d FUSD", ghostFeesPulled / 1 ether);
        console.log("  Pool paid:        %d FUSD", ghostPoolPaid / 1 ether);
        console.log("  Treasury out:     %d FUSD", ghostTreasuryWithdrawn / 1 ether);
        console.log("  Awards out:       %d FUSD", ghostAwardsPaid / 1 ether);
        console.log("  Contract balance: %d FUSD", token.balanceOf(address(membership)) / 1 ether);
    }

    // ══════════════════════════════════════════════════════════════════
    //  ADMIN ROLES  (isolated so a failure points precisely)
    // ══════════════════════════════════════════════════════════════════

    function test_Stress300_AdminRoles_And_AccessControl() public {
        _seed(30, 0);

        // ── updateStageFee takes effect on the NEXT join ──────────────
        vm.prank(admin);
        membership.updateStageFee(0, 30 ether, 8 ether);

        (address p, BinaryMembershipV1.Side s) = membership.findOpenSlot(root, 0);
        uint256 pBefore = token.balanceOf(p);
        uint256 uBefore = token.balanceOf(users[30]);
        uint256 pendBefore = membership.pendingTreasury();

        vm.prank(users[30]);
        membership.register(root, p, s);

        assertEq(token.balanceOf(p) - pBefore, 8 ether, "new nodeReward not applied");
        assertEq(uBefore - token.balanceOf(users[30]), 30 ether, "new fee not applied");
        assertEq(
            membership.pendingTreasury() - pendBefore,
            22 ether,
            "new treasury split wrong"
        );

        // invalid configs rejected
        vm.expectRevert(BinaryMembershipV1.InvalidFeeConfig.selector);
        vm.prank(admin);
        membership.updateStageFee(0, 10 ether, 10 ether);

        vm.expectRevert(BinaryMembershipV1.InvalidFeeConfig.selector);
        vm.prank(admin);
        membership.updateStageFee(0, 0, 1 ether);

        // ── updateAwardThreshold ─────────────────────────────────────
        vm.prank(admin);
        membership.updateAwardThreshold(1, 2);
        assertEq(membership.getStageConfig(1).rolloversForAward, 2, "threshold not set");

        // ── setStageOpen ─────────────────────────────────────────────
        vm.prank(admin);
        membership.setStageOpen(0, false);
        (address p2, BinaryMembershipV1.Side s2) = membership.findOpenSlot(root, 0);
        vm.expectRevert(
            abi.encodeWithSelector(BinaryMembershipV1.StageClosed.selector, uint256(0))
        );
        vm.prank(users[31]);
        membership.register(root, p2, s2);

        vm.prank(admin);
        membership.setStageOpen(0, true);
        vm.prank(users[31]);
        membership.register(root, p2, s2);

        // ── pause / unpause ──────────────────────────────────────────
        vm.prank(pauser);
        membership.pause();
        (address p3, BinaryMembershipV1.Side s3) = membership.findOpenSlot(root, 0);
        vm.expectRevert();
        vm.prank(users[32]);
        membership.register(root, p3, s3);
        vm.prank(pauser);
        membership.unpause();
        vm.prank(users[32]);
        membership.register(root, p3, s3);

        // ── setTreasury ──────────────────────────────────────────────
        address newT = address(0xFEED);
        vm.prank(admin);
        membership.setTreasury(newT);
        assertEq(membership.treasury(), newT, "treasury not updated");

        vm.expectRevert(BinaryMembershipV1.ZeroAddress.selector);
        vm.prank(admin);
        membership.setTreasury(address(0));

        // ── every admin fn rejects outsiders ─────────────────────────
        vm.startPrank(outsider);
        vm.expectRevert();
        membership.updateStageFee(0, 30 ether, 8 ether);
        vm.expectRevert();
        membership.updateAwardThreshold(1, 3);
        vm.expectRevert();
        membership.setStageOpen(0, false);
        vm.expectRevert();
        membership.setCycleGuardEnabled(true);
        vm.expectRevert();
        membership.setTreasury(outsider);
        vm.expectRevert();
        membership.pause();
        vm.expectRevert();
        membership.enrollStageRoot(root, 1);
        vm.stopPrank();

        // withdrawing to the NEW treasury address must credit the new one
        uint256 pend = membership.pendingTreasury();
        vm.prank(treasuryWallet); // still holds TREASURY_ROLE
        membership.withdrawTreasury(pend);
        assertEq(token.balanceOf(newT), pend, "funds did not go to new treasury");
    }

    // ══════════════════════════════════════════════════════════════════
    //  ADVERSARIAL / LOOPHOLE PROBES
    // ══════════════════════════════════════════════════════════════════

    function test_Stress300_Adversarial_Probes() public {
        _seed(60, 0);

        // 1. Cannot register twice
        vm.expectRevert(BinaryMembershipV1.AlreadyRegistered.selector);
        vm.prank(users[0]);
        membership.register(root, root, BinaryMembershipV1.Side.Left);

        // 2. Cannot use an unregistered sponsor
        (address p, BinaryMembershipV1.Side s) = membership.findOpenSlot(root, 0);
        vm.expectRevert(BinaryMembershipV1.SponsorNotRegistered.selector);
        vm.prank(users[60]);
        membership.register(outsider, p, s);

        // 3. Cannot place under a parent not enrolled in that stage
        vm.expectRevert(
            abi.encodeWithSelector(
                BinaryMembershipV1.ParentNotInStage.selector, outsider, uint256(0)
            )
        );
        vm.prank(users[60]);
        membership.register(root, outsider, BinaryMembershipV1.Side.Left);

        // 4. Cannot skip a stage
        vm.prank(operator);
        membership.enrollStageRoot(root, 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                BinaryMembershipV1.PreviousStageRequired.selector, uint256(1)
            )
        );
        vm.prank(users[0]);
        membership.joinStage(2, root, BinaryMembershipV1.Side.Left);

        // 5. Cannot join the same stage twice
        vm.prank(users[0]);
        membership.joinStage(1, root, BinaryMembershipV1.Side.Left);
        (address p1, BinaryMembershipV1.Side s1) = membership.findOpenSlot(root, 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                BinaryMembershipV1.AlreadyEnrolledInStage.selector, uint256(1)
            )
        );
        vm.prank(users[0]);
        membership.joinStage(1, p1, s1);

        // 6. Cannot take an occupied slot
        vm.expectRevert(
            abi.encodeWithSelector(
                BinaryMembershipV1.SlotOccupied.selector, root, BinaryMembershipV1.Side.Left
            )
        );
        vm.prank(users[1]);
        membership.joinStage(1, root, BinaryMembershipV1.Side.Left);

        // 7. Side.None is rejected
        vm.expectRevert(BinaryMembershipV1.InvalidSide.selector);
        vm.prank(users[60]);
        membership.register(root, root, BinaryMembershipV1.Side.None);

        // 8. Stage id out of range
        vm.expectRevert(
            abi.encodeWithSelector(BinaryMembershipV1.InvalidStage.selector, uint256(6))
        );
        vm.prank(users[0]);
        membership.joinStage(6, root, BinaryMembershipV1.Side.Left);

        // 9. Insufficient balance cannot mint value from nothing
        address broke = address(0xB0B);
        vm.prank(broke);
        token.approve(address(membership), type(uint256).max);
        (address pb, BinaryMembershipV1.Side sb) = membership.findOpenSlot(root, 0);
        vm.expectRevert();
        vm.prank(broke);
        membership.register(root, pb, sb);

        // 10. Solvency still holds after all of the above
        assertGe(
            token.balanceOf(address(membership)),
            membership.pendingTreasury(),
            "insolvent after adversarial probes"
        );
    }

    /// @notice Detached boards stay live under the guard without crediting the
    ///         ancestor that rolled them out.
    function test_Stress300_CycleGuard_UnderLoad() public {
        vm.prank(admin);
        membership.setCycleGuardEnabled(true);

        // Drive many rollovers with the guard ON — BFS placement must never trip it
        _seed(120, 0);

        (,,, uint256 rollovers,,) = membership.getTreeInfo(root, 0);
        assertEq(rollovers, 120 / 6, "rollovers wrong under cycle guard");

        BinaryMembershipV1.StageMembership memory before =
            membership.getStageMembership(root, 0);

        // users[2] sat inside cycle 1 and is now below a stale users[0] -> root
        // edge. It remains a valid independent board parent.
        vm.prank(users[120]);
        membership.register(root, users[2], BinaryMembershipV1.Side.Left);
        BinaryMembershipV1.StageMembership memory afterMem =
            membership.getStageMembership(root, 0);
        assertTrue(membership.getMember(users[120]).active, "detached placement failed");
        assertEq(afterMem.slotsFilledBelow, before.slotsFilledBelow, "root credited after detachment");
        assertEq(afterMem.rolloverCount, before.rolloverCount, "root rolled after detachment");
    }

    // ── helper ───────────────────────────────────────────────────────

    function _seed(uint256 count, uint256 stageId) internal {
        for (uint256 i = 0; i < count; i++) {
            (address parent, BinaryMembershipV1.Side side) =
                membership.findOpenSlot(root, stageId);
            vm.prank(users[i]);
            membership.register(root, parent, side);
        }
    }
}
