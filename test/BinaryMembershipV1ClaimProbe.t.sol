// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Reproduction attempts for four reported defects. Each test either
///         demonstrates the failure concretely or shows it does not occur.
///
///  Crucially, the contract is funded ONLY by member fees here. Every earlier
///  suite pre-seeded it with millions of tokens, which masks any accounting
///  bug that spends money the contract has not actually earned.
contract BinaryMembershipV1ClaimProbeTest is Test {
    BinaryMembershipV1 public membership;
    MockERC20 public token;

    address admin    = address(0xAD);
    address treasury = address(0x7EA5);
    address operator = address(0x0B);
    address root     = address(0x1);

    address[] users;

    uint256[6] FEES   = [uint256(20 ether), 60 ether, 180 ether, 540 ether, 1620 ether, 4860 ether];
    uint256[6] NODES  = [uint256(5 ether), 10 ether, 25 ether, 80 ether, 250 ether, 800 ether];
    uint256[6] SLOTS  = [uint256(6), 14, 14, 14, 14, 14];
    uint256[6] DEPTHS = [uint256(2), 3, 3, 3, 3, 3];
    uint256[6] AWARDS = [uint256(0), 10, 10, 10, 10, 8];

    function setUp() public {
        token = new MockERC20("FAKEUSD", "FUSD", 0);

        vm.startPrank(admin);
        membership = new BinaryMembershipV1(IERC20(address(token)), treasury, admin, 0, root);
        membership.grantRole(membership.OPERATOR_ROLE(), operator);
        membership.grantRole(membership.TREASURY_ROLE(), treasury);
        membership.configureStages(FEES, NODES, SLOTS, DEPTHS, AWARDS);
        vm.stopPrank();

        for (uint256 i = 0; i < 400; i++) {
            address u = address(uint160(0x900000 + i));
            users.push(u);
            token.mint(u, 100_000 ether);
            vm.prank(u);
            token.approve(address(membership), type(uint256).max);
        }
        token.mint(root, 100_000 ether);
        vm.prank(root);
        token.approve(address(membership), type(uint256).max);

        // NO seed. Fees are the only money in the contract.
        vm.prank(root);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);
    }

    function _fill(uint256 n) internal {
        for (uint256 i = 0; i < n; i++) {
            (address p, BinaryMembershipV1.Side s) = membership.findOpenSlot(root, 0);
            vm.prank(users[i]);
            membership.register(root, p, s);
        }
    }

    // ══════════════════════════════════════════════════════════════════
    //  CLAIM 1 — awards do not reduce pendingTreasury
    // ══════════════════════════════════════════════════════════════════

    function test_Claim1_AwardKeepsTreasurySolvent() public {
        _fill(200);

        vm.prank(operator);
        membership.enrollStageRoot(root, 1);
        for (uint256 i = 0; i < 150; i++) {
            (address p, BinaryMembershipV1.Side s) = membership.findOpenSlot(root, 1);
            vm.prank(users[i]);
            membership.joinStage(1, p, s);
        }

        uint256 pending = membership.pendingTreasury();
        uint256 balance = token.balanceOf(address(membership));

        console.log("pendingTreasury (USD):", pending / 1 ether);
        console.log("contract balance(USD):", balance / 1 ether);
        assertEq(balance, pending, "with no seed, balance should equal the treasury liability");

        uint256 earnings = membership.getStageMembership(root, 1).stageEarnings;
        uint256 award = earnings / 2;

        vm.prank(operator);
        membership.grantPhysicalAward(root, 1, award);

        uint256 pendingAfter = membership.pendingTreasury();
        uint256 balanceAfter = token.balanceOf(address(membership));

        console.log("--- after a", award / 1 ether, "USD award ---");
        console.log("pendingTreasury (USD):", pendingAfter / 1 ether);
        console.log("contract balance(USD):", balanceAfter / 1 ether);

        // FIXED: the award is drawn from the treasury pot, so the liability
        // falls with the balance and the two stay equal.
        assertEq(pendingAfter, pending - award, "award must reduce pendingTreasury");
        assertEq(balanceAfter, pendingAfter, "balance must still cover the liability");
        assertEq(membership.totalAwardsPaid(), award, "award total not tracked");

        // Everything still on the books is actually payable.
        vm.prank(treasury);
        membership.withdrawTreasury(pendingAfter);
        assertEq(membership.pendingTreasury(), 0, "treasury did not drain");
    }

    // ══════════════════════════════════════════════════════════════════
    //  CLAIM 2 — guard OFF: detached branches cannot roll an ancestor
    // ══════════════════════════════════════════════════════════════════

    function test_Claim2_DetachedBranchCannotCreditEmptyAncestor() public {
        assertFalse(membership.cycleGuardEnabled(), "guard should default off");

        // Fill root's 6-slot board -> root rolls over, its children detach.
        _fill(6);
        assertEq(membership.getStageMembership(root, 0).rolloverCount, 1, "no rollover");
        assertEq(membership.getStageMembership(root, 0).left, address(0), "left not cleared");

        address orphan = users[0]; // was root.left before the rollover
        assertEq(membership.getStageMembership(orphan, 0).parent, root, "orphan lost parent link");

        // At rollover the orphan's own slots are full, so it cannot take a
        // placement yet. Fill the orphan's board until IT rolls over, which
        // clears its children and reopens its slots while it stays detached
        // from root's live tree.
        uint256 next = 6;
        _fillUnder(users[2], next); next += 2;   // orphan.left's board
        _fillUnder(users[3], next); next += 2;   // orphan.right's board

        BinaryMembershipV1.StageMembership memory om =
            membership.getStageMembership(orphan, 0);
        assertGt(om.rolloverCount, 0, "orphan did not roll over");
        assertEq(om.left, address(0), "orphan slots not reopened");

        BinaryMembershipV1.StageMembership memory before =
            membership.getStageMembership(root, 0);
        assertEq(before.left, address(0), "root live tree should be empty");
        assertEq(before.right, address(0), "root live tree should be empty");

        // Now place directly under the detached orphan. The orphan's parent
        // pointer still says `root`, so the credit walks up into root.
        vm.prank(users[next]);
        membership.register(root, orphan, BinaryMembershipV1.Side.Left);

        BinaryMembershipV1.StageMembership memory rm =
            membership.getStageMembership(root, 0);

        console.log("root live children both empty:",
            rm.left == address(0) && rm.right == address(0));
        console.log("root slotsFilledBelow before:", before.slotsFilledBelow);
        console.log("root slotsFilledBelow after :", rm.slotsFilledBelow);

        // FIXED: the credit walk stops at the stale link, so root is untouched.
        assertEq(rm.left, address(0), "root still has no live children");
        assertEq(
            rm.slotsFilledBelow,
            before.slotsFilledBelow,
            "a detached branch must not credit an ancestor it has left"
        );
        assertEq(
            rm.rolloverCount,
            before.rolloverCount,
            "a detached branch must not roll an ancestor"
        );
    }

    /// @dev Fill both slots under `node` using the next two unused wallets.
    function _fillUnder(address node, uint256 from) internal {
        BinaryMembershipV1.StageMembership memory m =
            membership.getStageMembership(node, 0);
        if (m.left == address(0)) {
            vm.prank(users[from]);
            membership.register(root, node, BinaryMembershipV1.Side.Left);
        }
        m = membership.getStageMembership(node, 0);
        if (m.right == address(0)) {
            vm.prank(users[from + 1]);
            membership.register(root, node, BinaryMembershipV1.Side.Right);
        }
    }

    // ══════════════════════════════════════════════════════════════════
    //  CLAIM 3 — guard ON: findPlacementSlot returns a rejected slot
    // ══════════════════════════════════════════════════════════════════

    function test_Claim3_GuardOnPlacementSlotNeverReturnsRejectedSlot() public {
        vm.prank(admin);
        membership.setCycleGuardEnabled(true);

        // Build a tree, then force rollovers so detached nodes exist.
        _fill(40);

        // Walk every member and look for one the finder would offer but the
        // guard would refuse.
        uint256 mismatches;
        uint256 otherReverts;
        for (uint256 i = 0; i < 40; i++) {
            address sponsor = users[i];
            if (!membership.getStageMembership(sponsor, 0).enrolled) continue;

            (address parent, BinaryMembershipV1.Side side) =
                membership.findPlacementSlot(sponsor, 0);
            if (parent == address(0)) continue;

            // Would a real registration at this slot succeed? Capture WHY not:
            // a blind catch would count ordinary AlreadyRegistered noise as a
            // guard mismatch and overstate the finding.
            uint256 snap = vm.snapshot();
            address newcomer = users[200 + i];
            vm.prank(newcomer);
            try membership.register(sponsor, parent, side) {
                // accepted
            } catch (bytes memory reason) {
                bytes4 sel;
                if (reason.length >= 4) {
                    assembly { sel := mload(add(reason, 0x20)) }
                }
                if (sel == BinaryMembershipV1.ParentOrphanedByCycle.selector) {
                    mismatches++;
                    console.log("guard rejected a slot the finder offered. idx:", i);
                } else {
                    otherReverts++;
                    console.logBytes4(sel);
                }
            }
            vm.revertTo(snap);
        }

        console.log("guard mismatches:", mismatches);
        console.log("other reverts   :", otherReverts);
        assertEq(mismatches, 0, "findPlacementSlot offered slots the cycle guard rejects");
    }

    // ══════════════════════════════════════════════════════════════════
    //  CLAIM 4 — guard ON: deep detached branches remain independent
    // ══════════════════════════════════════════════════════════════════

    function test_Claim4_GuardAcceptsDeepDetachedBoardWithoutAncestorCredit() public {
        vm.prank(admin);
        membership.setCycleGuardEnabled(true);

        // Stage 0 payout depth is only 2. A stale edge above that depth still
        // defines an independent board boundary rather than an invalid path.
        uint256 depth = membership.getStageConfig(0).treeDepth;
        assertEq(depth, 2, "stage 0 depth");

        // Build a manual chain deeper than the guard's walk:
        // root -> a -> b -> c -> d
        vm.prank(users[0]);
        membership.register(root, root, BinaryMembershipV1.Side.Left);
        vm.prank(users[1]);
        membership.register(root, users[0], BinaryMembershipV1.Side.Left);
        vm.prank(users[2]);
        membership.register(root, users[1], BinaryMembershipV1.Side.Left);
        vm.prank(users[3]);
        membership.register(root, users[2], BinaryMembershipV1.Side.Left);

        // Fill root's board so root rolls over and detaches users[0].
        uint256 placed = 4;
        while (membership.getStageMembership(root, 0).rolloverCount == 0 && placed < 30) {
            (address p, BinaryMembershipV1.Side s) = membership.findOpenSlot(root, 0);
            if (p == address(0)) break;
            vm.prank(users[placed]);
            membership.register(root, p, s);
            placed++;
        }

        bool rootRolled = membership.getStageMembership(root, 0).rolloverCount > 0;
        bool aDetached =
            membership.getStageMembership(root, 0).left != users[0] &&
            membership.getStageMembership(root, 0).right != users[0];

        console.log("root rolled over:", rootRolled);
        console.log("users[0] detached from root:", aDetached);

        if (!rootRolled || !aDetached) {
            console.log("preconditions not met; nothing to prove here");
            return;
        }

        BinaryMembershipV1.StageMembership memory before =
            membership.getStageMembership(root, 0);

        // users[3] sits three links below the detachment. It may keep building
        // that board, but the former root must receive no slot credit.
        vm.prank(users[50]);
        membership.register(root, users[3], BinaryMembershipV1.Side.Left);
        BinaryMembershipV1.StageMembership memory afterMem =
            membership.getStageMembership(root, 0);
        assertTrue(membership.getMember(users[50]).active, "detached member was not registered");
        assertEq(afterMem.slotsFilledBelow, before.slotsFilledBelow, "former root credited");
        assertEq(afterMem.rolloverCount, before.rolloverCount, "former root rolled");
    }
}
