// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Independent audit probes added for the 2,000-wallet review.
/// @dev The finding tests intentionally assert the contract's current, unsafe
///      behaviour so the suite remains green while preserving reproducible
///      evidence. They should be inverted when the corresponding defect is fixed.
contract BinaryMembershipV1Stress2000AuditTest is Test {
    BinaryMembershipV1 internal membership;
    MockERC20 internal token;

    address internal constant ADMIN = address(0xAD);
    address internal constant TREASURY = address(0x7EA5);
    address internal constant OPERATOR = address(0x0B);
    address internal constant ROOT = address(0x1);

    uint256 internal constant WALLETS = 2_000; // ROOT + 1,999 paying members

    uint256[6] internal FEES =
        [uint256(20 ether), 60 ether, 180 ether, 540 ether, 1620 ether, 4860 ether];
    uint256[6] internal NODES =
        [uint256(5 ether), 10 ether, 25 ether, 80 ether, 250 ether, 800 ether];
    uint256[6] internal SLOTS = [uint256(6), 14, 14, 14, 14, 14];
    uint256[6] internal DEPTHS = [uint256(2), 3, 3, 3, 3, 3];
    uint256[6] internal AWARDS = [uint256(0), 10, 10, 10, 10, 8];

    function setUp() public {
        token = new MockERC20("FAKEUSD", "FUSD", 18);

        vm.startPrank(ADMIN);
        membership = new BinaryMembershipV1(
            IERC20(address(token)), TREASURY, ADMIN, 0, ROOT
        );
        membership.grantRole(membership.OPERATOR_ROLE(), OPERATOR);
        membership.grantRole(membership.TREASURY_ROLE(), TREASURY);
        membership.configureStages(FEES, NODES, SLOTS, DEPTHS, AWARDS);
        vm.stopPrank();

        vm.prank(ROOT);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);
    }

    function _user(uint256 index) internal pure returns (address) {
        return address(uint160(0x200000 + index));
    }

    function _fundAndApprove(address user, uint256 amount) internal {
        token.mint(user, amount);
        vm.prank(user);
        token.approve(address(membership), type(uint256).max);
    }

    function _expectedPayout(address parent, uint256 stageId)
        internal
        view
        returns (uint256 payout)
    {
        address current = parent;
        for (uint256 level; level < DEPTHS[stageId] && current != address(0); level++) {
            payout += NODES[stageId];

            BinaryMembershipV1.StageMembership memory mem =
                membership.getStageMembership(current, stageId);
            address par = mem.parent;
            if (par == address(0)) break;

            BinaryMembershipV1.StageMembership memory parMem =
                membership.getStageMembership(par, stageId);
            if (parMem.left != current && parMem.right != current) break;
            current = par;
        }
    }

    /// @notice All 2,000 wallets traverse all six stages. Every one of the
    ///         11,994 paid placements is checked independently for its exact
    ///         upline payout; all member earnings are then reconciled to the pool.
    function test_Stress2000_AllWallets_AllSixStages() public {
        // A single Foundry test is one synthetic transaction and its default
        // ~1.07B gas ceiling is lower than 11,994 real transactions combined.
        // Pause synthetic metering; every individual join remains bounded and
        // is covered by the dedicated gas tests in the existing suite.
        vm.pauseGasMetering();

        uint256 perWalletFunding;
        for (uint256 s; s < 6; s++) perWalletFunding += FEES[s];

        // Stage 0: ROOT plus 1,999 paying registrations.
        for (uint256 i; i < WALLETS - 1; i++) {
            address user = _user(i);
            _fundAndApprove(user, perWalletFunding);

            (address parent, BinaryMembershipV1.Side side) =
                membership.findPlacementSlot(ROOT, 0);
            uint256 expected = _expectedPayout(parent, 0);
            uint256 beforePool = membership.totalPoolPaid();

            vm.prank(user);
            membership.register(ROOT, parent, side);

            assertEq(membership.totalPoolPaid() - beforePool, expected, "stage0 payout");
        }
        assertEq(membership.memberCount(), WALLETS, "not exactly 2,000 wallets");

        // All 1,999 paying members traverse stages 1..5. ROOT is the single
        // operator-seeded anchor at each stage and therefore pays no stage fee.
        for (uint256 s = 1; s < 6; s++) {
            vm.prank(OPERATOR);
            membership.enrollStageRoot(ROOT, s);

            for (uint256 i; i < WALLETS - 1; i++) {
                address user = _user(i);
                (address parent, BinaryMembershipV1.Side side) =
                    membership.findPlacementSlot(ROOT, s);
                uint256 expected = _expectedPayout(parent, s);
                uint256 beforePool = membership.totalPoolPaid();

                vm.prank(user);
                membership.joinStage(s, parent, side);

                assertEq(membership.totalPoolPaid() - beforePool, expected, "stage payout");
            }
        }

        uint256 expectedFees = (WALLETS - 1) * perWalletFunding;
        assertEq(
            membership.totalPoolPaid() + membership.totalTreasuryPaid(),
            expectedFees,
            "fees are not conserved"
        );
        assertEq(membership.pendingTreasury(), membership.totalTreasuryPaid());
        assertEq(token.balanceOf(address(membership)), membership.pendingTreasury());

        // Reconcile every stage ledger and every member's aggregate ledger.
        uint256 allStageEarnings;
        uint256 ordinaryEarners;
        uint256 ordinaryEarnings;
        uint256 totalRollovers;
        for (uint256 s; s < 6; s++) {
            uint256 stageSum;
            BinaryMembershipV1.StageMembership memory rootMem =
                membership.getStageMembership(ROOT, s);
            stageSum += rootMem.stageEarnings;
            totalRollovers += rootMem.rolloverCount;
            assertEq(rootMem.rolloverCount, (WALLETS - 1) / SLOTS[s], "root rollovers");
            assertEq(rootMem.slotsFilledBelow, (WALLETS - 1) % SLOTS[s], "root remainder");

            for (uint256 i; i < WALLETS - 1; i++) {
                BinaryMembershipV1.StageMembership memory mem =
                    membership.getStageMembership(_user(i), s);
                assertTrue(mem.enrolled, "wallet missing a stage");
                assertLt(mem.slotsFilledBelow, SLOTS[s], "slot counter escaped board size");
                stageSum += mem.stageEarnings;
                totalRollovers += mem.rolloverCount;
            }
            allStageEarnings += stageSum;
        }
        assertEq(allStageEarnings, membership.totalPoolPaid(), "stage ledgers != pool");

        for (uint256 i; i < WALLETS - 1; i++) {
            uint256 sum;
            for (uint256 s; s < 6; s++) {
                sum += membership.getStageMembership(_user(i), s).stageEarnings;
            }
            assertEq(membership.getMember(_user(i)).totalEarned, sum, "member ledger drift");
            if (sum > 0) {
                ordinaryEarners++;
                ordinaryEarnings += sum;
            }
        }

        uint256 rootEarnings = membership.getMember(ROOT).totalEarned;
        assertEq(rootEarnings + ordinaryEarnings, membership.totalPoolPaid());
        assertGt(ordinaryEarners, 0, "spillunder never paid an ordinary member");
        assertGt(totalRollovers, 0, "rollover path was not exercised");

        console.log("wallets                    :", WALLETS);
        console.log("paid placements            :", (WALLETS - 1) * 6);
        console.log("fees collected (tokens)    :", expectedFees / 1 ether);
        console.log("pool paid (tokens)         :", membership.totalPoolPaid() / 1 ether);
        console.log("treasury accrued (tokens)  :", membership.totalTreasuryPaid() / 1 ether);
        console.log("root earnings (tokens)     :", rootEarnings / 1 ether);
        console.log("ordinary spillunder earners:", ordinaryEarners);
        console.log("ordinary earnings (tokens) :", ordinaryEarnings / 1 ether);
        console.log("all rollovers              :", totalRollovers);

        vm.resumeGasMetering();
    }

    /// @notice Post-fix campaign: 3,000 wallets, all six stages, deterministic
    ///         mixed sponsorship, cycle guard ON, no masking contract prefund.
    ///         Every placement is checked against an independent stale-aware
    ///         payout walk and every member ledger is reconciled afterwards.
    function test_PostFix3000_MixedSponsorsGuarded_AllSixStages() public {
        vm.pauseGasMetering();

        uint256 wallets = 3_000;
        uint256 paying = wallets - 1;
        uint256 perWalletFunding;
        for (uint256 s; s < 6; s++) perWalletFunding += FEES[s];

        vm.prank(ADMIN);
        membership.setCycleGuardEnabled(true);

        // Bucket 0 is ROOT; bucket i+1 is _user(i).
        uint256[] memory sponsorCounts = new uint256[](wallets);
        uint256 maxSponsorCount;

        for (uint256 i; i < paying; i++) {
            address user = _user(i);
            _fundAndApprove(user, perWalletFunding);

            uint256 sponsorBucket;
            address sponsor;
            if (i == 0) {
                sponsor = ROOT;
                sponsorBucket = 0;
            } else {
                uint256 sponsorIndex =
                    uint256(keccak256(abi.encodePacked("MIXED-SPONSOR", i))) % i;
                sponsor = _user(sponsorIndex);
                sponsorBucket = sponsorIndex + 1;
            }
            sponsorCounts[sponsorBucket]++;
            if (sponsorCounts[sponsorBucket] > maxSponsorCount) {
                maxSponsorCount = sponsorCounts[sponsorBucket];
            }

            (address parent, BinaryMembershipV1.Side side) =
                membership.findPlacementSlot(sponsor, 0);
            uint256 expected = _expectedPayout(parent, 0);
            uint256 beforePool = membership.totalPoolPaid();

            vm.prank(user);
            membership.register(sponsor, parent, side);
            assertEq(membership.totalPoolPaid() - beforePool, expected, "guarded s0 payout");
        }

        // Sponsors always have a lower index and therefore enter each higher
        // stage before their recruits. This heavily exercises sponsor-first
        // placement while rollovers continuously detach old boards.
        for (uint256 s = 1; s < 6; s++) {
            vm.prank(OPERATOR);
            membership.enrollStageRoot(ROOT, s);

            for (uint256 i; i < paying; i++) {
                address user = _user(i);
                address sponsor = membership.getMember(user).sponsor;
                (address parent, BinaryMembershipV1.Side side) =
                    membership.findPlacementSlot(sponsor, s);
                uint256 expected = _expectedPayout(parent, s);
                uint256 beforePool = membership.totalPoolPaid();

                vm.prank(user);
                membership.joinStage(s, parent, side);
                assertEq(
                    membership.totalPoolPaid() - beforePool,
                    expected,
                    "guarded higher-stage payout"
                );
            }
        }

        _verifyAndReportPostFix3000(wallets, paying * perWalletFunding, maxSponsorCount);
        vm.resumeGasMetering();
    }

    function _verifyAndReportPostFix3000(
        uint256 wallets,
        uint256 expectedFees,
        uint256 maxSponsorCount
    ) internal view {
        uint256 paying = wallets - 1;
        assertEq(membership.memberCount(), wallets, "3,000-wallet count drift");
        assertEq(
            membership.totalPoolPaid() + membership.totalTreasuryPaid(),
            expectedFees,
            "guarded fee conservation"
        );
        assertEq(token.balanceOf(address(membership)), membership.pendingTreasury());

        uint256 stageLedger;
        uint256 memberLedger;
        uint256 ordinaryEarners;
        uint256 zeroEarners;
        uint256 totalRollovers;
        uint256 richestOrdinary;

        for (uint256 s; s < 6; s++) {
            BinaryMembershipV1.StageMembership memory rootMem =
                membership.getStageMembership(ROOT, s);
            stageLedger += rootMem.stageEarnings;
            totalRollovers += rootMem.rolloverCount;
        }

        for (uint256 i; i < paying; i++) {
            address user = _user(i);
            uint256 walletStages;
            for (uint256 s; s < 6; s++) {
                BinaryMembershipV1.StageMembership memory mem =
                    membership.getStageMembership(user, s);
                assertTrue(mem.enrolled, "mixed wallet missing stage");
                assertLt(mem.slotsFilledBelow, SLOTS[s], "mixed slot overflow");
                walletStages += mem.stageEarnings;
                stageLedger += mem.stageEarnings;
                totalRollovers += mem.rolloverCount;
            }
            assertEq(membership.getMember(user).totalEarned, walletStages, "mixed ledger drift");
            memberLedger += walletStages;
            if (walletStages == 0) {
                zeroEarners++;
            } else {
                ordinaryEarners++;
                if (walletStages > richestOrdinary) richestOrdinary = walletStages;
            }
        }

        uint256 rootEarnings = membership.getMember(ROOT).totalEarned;
        assertEq(stageLedger, membership.totalPoolPaid(), "all stage ledgers != pool");
        assertEq(memberLedger + rootEarnings, membership.totalPoolPaid(), "member sum != pool");
        assertGt(ordinaryEarners, wallets / 3, "earnings concentrated too narrowly");
        assertGt(totalRollovers, 0, "guarded campaign produced no rollovers");

        uint256 week = block.timestamp / 1 weeks;
        address top = membership.weeklyTopSponsor(week);
        assertEq(membership.weeklyTopCount(week), maxSponsorCount, "weekly top count drift");
        assertEq(membership.weeklySponsorCount(week, top), maxSponsorCount, "weekly top mismatch");

        console.log("guarded wallets             :", wallets);
        console.log("guarded paid placements     :", paying * 6);
        console.log("guarded fees (tokens)       :", expectedFees / 1 ether);
        console.log("guarded pool (tokens)       :", membership.totalPoolPaid() / 1 ether);
        console.log("guarded treasury (tokens)   :", membership.pendingTreasury() / 1 ether);
        console.log("guarded root earnings       :", rootEarnings / 1 ether);
        console.log("ordinary earners            :", ordinaryEarners);
        console.log("zero earners                :", zeroEarners);
        console.log("richest ordinary (tokens)   :", richestOrdinary / 1 ether);
        console.log("guarded total rollovers     :", totalRollovers);
        console.log("weekly top sponsor referrals:", maxSponsorCount);
    }

    /// @notice Client schedule regression at the boundary between the final
    ///         two stages: eight boards must still be insufficient at $1,620,
    ///         but must unlock the first award at $4,860.
    function test_AwardSchedule_SecondLastNeedsTen_LastNeedsEight() public {
        uint256 membersNeeded = 8 * SLOTS[5]; // 112 placements
        uint256 allFees;
        for (uint256 s; s < 6; s++) allFees += FEES[s];

        for (uint256 i; i < membersNeeded; i++) {
            address user = _user(i);
            _fundAndApprove(user, allFees);
            (address parent, BinaryMembershipV1.Side side) =
                membership.findOpenSlot(ROOT, 0);
            vm.prank(user);
            membership.register(ROOT, parent, side);
        }

        for (uint256 s = 1; s < 6; s++) {
            vm.prank(OPERATOR);
            membership.enrollStageRoot(ROOT, s);
            for (uint256 i; i < membersNeeded; i++) {
                (address parent, BinaryMembershipV1.Side side) =
                    membership.findOpenSlot(ROOT, s);
                vm.prank(_user(i));
                membership.joinStage(s, parent, side);
            }
        }

        (,, uint256 secondLastRollovers, uint256 secondLastMilestone, bool secondLastEligible) =
            membership.getAwardInfo(ROOT, 4);
        assertEq(secondLastRollovers, 8, "$1,620 rollover count");
        assertEq(secondLastMilestone, 10, "$1,620 threshold");
        assertFalse(secondLastEligible, "$1,620 must still require ten");

        (,, uint256 lastRollovers, uint256 lastMilestone, bool lastEligible) =
            membership.getAwardInfo(ROOT, 5);
        assertEq(lastRollovers, 8, "$4,860 rollover count");
        assertEq(lastMilestone, 8, "$4,860 threshold");
        assertTrue(lastEligible, "$4,860 must unlock at eight");

        vm.prank(OPERATOR);
        membership.grantPhysicalAward(ROOT, 5, 1 ether);

        (, uint256 lastAwarded,, uint256 nextMilestone, bool stillEligible) =
            membership.getAwardInfo(ROOT, 5);
        assertEq(lastAwarded, 8, "last-stage first milestone");
        assertEq(nextMilestone, 16, "last-stage repeat milestone");
        assertFalse(stillEligible, "second last-stage award unlocked early");
    }

    /// @notice REGRESSION (was HIGH): awards were paid from the contract balance
    ///         without reducing `pendingTreasury`, so the recorded treasury
    ///         claim outgrew the actual balance and the treasury could not
    ///         withdraw what its own books promised. Awards now draw from the
    ///         same pot they are paid out of.
    ///
    ///  This test deliberately runs with NO prefund. An oversized seed hides
    ///  the whole class of bug, which is exactly how it survived earlier runs.
    function test_Award_ReducesPendingTreasuryAndStaysSolvent() public {
        // 141 users are enough to register and produce ten stage-1 rollovers.
        for (uint256 i; i < 141; i++) {
            address user = _user(i);
            _fundAndApprove(user, FEES[0] + FEES[1]);
            (address p, BinaryMembershipV1.Side side) = membership.findOpenSlot(ROOT, 0);
            vm.prank(user);
            membership.register(ROOT, p, side);
        }

        vm.prank(OPERATOR);
        membership.enrollStageRoot(ROOT, 1);
        for (uint256 i; i < 140; i++) {
            (address p, BinaryMembershipV1.Side side) = membership.findOpenSlot(ROOT, 1);
            vm.prank(_user(i));
            membership.joinStage(1, p, side);
        }

        uint256 pendingBefore = membership.pendingTreasury();
        uint256 balanceBefore = token.balanceOf(address(membership));
        uint256 award = membership.getStageMembership(ROOT, 1).stageEarnings;
        assertEq(balanceBefore, pendingBefore, "test must have no masking prefund");
        assertGt(award, 0);

        vm.prank(OPERATOR);
        membership.grantPhysicalAward(ROOT, 1, award);

        assertEq(
            membership.pendingTreasury(),
            pendingBefore - award,
            "award must reduce the treasury liability"
        );
        assertEq(token.balanceOf(address(membership)), balanceBefore - award);
        assertEq(
            token.balanceOf(address(membership)),
            membership.pendingTreasury(),
            "balance must still cover the liability exactly"
        );
        assertEq(membership.totalAwardsPaid(), award, "award total not tracked");

        // Everything the books still promise is actually payable.
        uint256 remaining = membership.pendingTreasury();
        vm.prank(TREASURY);
        membership.withdrawTreasury(remaining);
        assertEq(membership.pendingTreasury(), 0, "treasury should drain cleanly");
    }

    /// @notice An award larger than the treasury can fund is refused outright
    ///         rather than quietly overdrawing the contract.
    function test_Award_CannotExceedTreasuryBalance() public {
        for (uint256 i; i < 141; i++) {
            address user = _user(i);
            _fundAndApprove(user, FEES[0] + FEES[1]);
            (address p, BinaryMembershipV1.Side side) = membership.findOpenSlot(ROOT, 0);
            vm.prank(user);
            membership.register(ROOT, p, side);
        }

        vm.prank(OPERATOR);
        membership.enrollStageRoot(ROOT, 1);
        for (uint256 i; i < 140; i++) {
            (address p, BinaryMembershipV1.Side side) = membership.findOpenSlot(ROOT, 1);
            vm.prank(_user(i));
            membership.joinStage(1, p, side);
        }

        // Drain the treasury, then try to award from an empty pot.
        uint256 pending = membership.pendingTreasury();
        vm.prank(TREASURY);
        membership.withdrawTreasury(pending);

        vm.prank(OPERATOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                BinaryMembershipV1.InsufficientPendingTreasury.selector, 0, 1
            )
        );
        membership.grantPhysicalAward(ROOT, 1, 1);
    }

    /// @notice REGRESSION (was MEDIUM): with the guard on, the placement helper
    ///         returned parents that `register` then rejected — measured at 36
    ///         of 40 sponsors, which would have broken placement for almost
    ///         everyone. Finder and guard now share one liveness predicate, so
    ///         they cannot disagree.
    function test_PlacementHelper_OnlyOffersSlotsRegisterAccepts() public {
        for (uint256 i; i < 7; i++) _fundAndApprove(_user(i), FEES[0]);

        for (uint256 i; i < 6; i++) {
            (address p, BinaryMembershipV1.Side side) = membership.findOpenSlot(ROOT, 0);
            vm.prank(_user(i));
            membership.register(ROOT, p, side);
        }

        vm.prank(ADMIN);
        membership.setCycleGuardEnabled(true);

        // _user(0)'s branch was detached by ROOT's rollover. It is now an
        // independent board, so the helper must keep the recruit inside it.
        (address returnedParent, BinaryMembershipV1.Side returnedSide) =
            membership.findPlacementSlot(_user(0), 0);
        assertTrue(returnedParent != address(0), "helper returned no slot");

        address cursor = returnedParent;
        bool insideDetachedBoard;
        for (uint256 links; links < 64 && cursor != address(0); links++) {
            if (cursor == _user(0)) {
                insideDetachedBoard = true;
                break;
            }
            cursor = membership.getStageMembership(cursor, 0).parent;
        }
        assertTrue(insideDetachedBoard, "helper abandoned detached sponsor board");

        // Whatever it offered, registration must succeed.
        vm.prank(_user(6));
        membership.register(_user(0), returnedParent, returnedSide);
        assertEq(
            membership.getStageMembership(_user(6), 0).parent,
            returnedParent,
            "placement did not land where the helper said"
        );
    }

    /// @notice A stale edge above treeDepth is an independent board boundary;
    ///         the branch remains placeable but cannot credit the former root.
    function test_CycleGuard_AcceptsDetachmentBeyondBoardDepthWithoutRootCredit() public {
        for (uint256 i; i < 10; i++) _fundAndApprove(_user(i), FEES[0]);

        for (uint256 i; i < 6; i++) {
            (address p, BinaryMembershipV1.Side side) = membership.findOpenSlot(ROOT, 0);
            vm.prank(_user(i));
            membership.register(ROOT, p, side);
        }

        // ROOT dropped user0's whole branch. Extend it while the guard is off
        // until the broken user0 -> ROOT edge is beyond the two-level check.
        vm.prank(_user(6));
        membership.register(ROOT, _user(2), BinaryMembershipV1.Side.Left);
        vm.prank(_user(7));
        membership.register(ROOT, _user(6), BinaryMembershipV1.Side.Left);

        vm.prank(ADMIN);
        membership.setCycleGuardEnabled(true);

        BinaryMembershipV1.StageMembership memory before =
            membership.getStageMembership(ROOT, 0);

        // user7 -> user6 -> user2 are intact and the broken user0 -> ROOT edge
        // terminates the independent board's upward path.
        vm.prank(_user(8));
        membership.register(ROOT, _user(7), BinaryMembershipV1.Side.Left);
        BinaryMembershipV1.StageMembership memory afterMem =
            membership.getStageMembership(ROOT, 0);
        assertTrue(membership.getMember(_user(8)).active, "detached placement failed");
        assertEq(afterMem.slotsFilledBelow, before.slotsFilledBelow, "ROOT received stale credit");
        assertEq(afterMem.rolloverCount, before.rolloverCount, "ROOT rolled from stale credit");
    }

    /// @notice REGRESSION (was HIGH, economic): with the guard off (the
    ///         default), stale parent links used to credit and roll ROOT even
    ///         though ROOT had no live child at any point. Both the reward walk
    ///         and the slot walk now stop at a detached link, so a branch ROOT
    ///         has dropped can no longer inflate ROOT's board.
    function test_StaleBranch_CannotRollDetachedAncestor() public {
        for (uint256 i; i < 40; i++) _fundAndApprove(_user(i), FEES[0]);

        // First legitimate board: ROOT rolls and drops user0/user1.
        for (uint256 i; i < 6; i++) {
            (address p, BinaryMembershipV1.Side side) = membership.findOpenSlot(ROOT, 0);
            vm.prank(_user(i));
            membership.register(ROOT, p, side);
        }
        assertEq(membership.getStageMembership(ROOT, 0).rolloverCount, 1);
        assertEq(membership.getStageMembership(ROOT, 0).left, address(0));

        // user0 started with two descendants. Four more placements beneath its
        // old children roll user0 and clear its own child pointers.
        uint256 next = 6;
        vm.prank(_user(next));
        membership.register(ROOT, _user(2), BinaryMembershipV1.Side.Left);
        next++;
        vm.prank(_user(next));
        membership.register(ROOT, _user(2), BinaryMembershipV1.Side.Right);
        next++;
        vm.prank(_user(next));
        membership.register(ROOT, _user(3), BinaryMembershipV1.Side.Left);
        next++;
        vm.prank(_user(next));
        membership.register(ROOT, _user(3), BinaryMembershipV1.Side.Right);
        next++;
        assertEq(membership.getStageMembership(_user(0), 0).rolloverCount, 1);

        // Three entirely detached user0 boards. Their six direct placements
        // are still propagated through user0's stale parent pointer to ROOT,
        // causing ROOT's second rollover with no live ROOT child at any time.
        for (uint256 cycle; cycle < 3; cycle++) {
            address left = _user(next++);
            address right = _user(next++);
            vm.prank(left);
            membership.register(ROOT, _user(0), BinaryMembershipV1.Side.Left);
            vm.prank(right);
            membership.register(ROOT, _user(0), BinaryMembershipV1.Side.Right);

            for (uint256 j; j < 2; j++) {
                address child = _user(next++);
                vm.prank(child);
                membership.register(
                    ROOT,
                    left,
                    j == 0 ? BinaryMembershipV1.Side.Left : BinaryMembershipV1.Side.Right
                );
            }
            for (uint256 j; j < 2; j++) {
                address child = _user(next++);
                vm.prank(child);
                membership.register(
                    ROOT,
                    right,
                    j == 0 ? BinaryMembershipV1.Side.Left : BinaryMembershipV1.Side.Right
                );
            }

            assertEq(membership.getStageMembership(ROOT, 0).left, address(0));
            assertEq(membership.getStageMembership(ROOT, 0).right, address(0));
        }

        // ROOT keeps the single rollover it earned legitimately. The detached
        // activity below rolls user0's own boards and stops there.
        assertEq(
            membership.getStageMembership(ROOT, 0).rolloverCount,
            1,
            "stale placements must not roll a detached ancestor"
        );
        assertEq(
            membership.getStageMembership(ROOT, 0).slotsFilledBelow,
            0,
            "ROOT must not be credited through a stale link"
        );
        assertGt(
            membership.getStageMembership(_user(0), 0).rolloverCount,
            1,
            "the detached branch should still cycle on its own"
        );
    }
}
