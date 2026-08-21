// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {MockUSDT18} from "../src/MockUSDT18.sol";

/// @notice 350 wallets divided into six terminal-stage cohorts, with a
///         different official board root at every stage and one global
///         treasury. Higher-stage cohorts traverse every prerequisite stage.
contract BinaryMembershipV1Stress350DistinctRootsTest is Test {
    uint256 internal constant UNIT = 1e18;
    uint256 internal constant WALLET_COUNT = 350;

    address internal constant ADMIN = address(0xAD);
    address internal constant OPERATOR = address(0x0B);
    address internal constant TREASURY = address(0x7EA5);

    MockUSDT18 internal token;
    BinaryMembershipV1 internal membership;

    address[WALLET_COUNT] internal wallets;
    address[6] internal stageRoots;
    mapping(address => uint256) internal terminalStage;

    uint256[6] internal cohortSizes = [uint256(59), 59, 58, 58, 58, 58];
    uint256[6] internal fees = [uint256(20 * UNIT), 60 * UNIT, 180 * UNIT, 540 * UNIT, 1_620 * UNIT, 4_860 * UNIT];
    uint256[6] internal rewards = [uint256(5 * UNIT), 10 * UNIT, 25 * UNIT, 80 * UNIT, 250 * UNIT, 800 * UNIT];
    uint256[6] internal slots = [uint256(6), 14, 14, 14, 14, 14];
    uint256[6] internal depths = [uint256(2), 3, 3, 3, 3, 3];

    function setUp() public {
        _assignWalletsAndCohorts();
        token = new MockUSDT18(ADMIN);

        vm.startPrank(ADMIN);
        membership = new BinaryMembershipV1(IERC20(address(token)), TREASURY, ADMIN, uint48(2 days), stageRoots[0]);
        membership.grantRole(membership.OPERATOR_ROLE(), OPERATOR);
        membership.grantRole(membership.TREASURY_ROLE(), TREASURY);
        membership.configureStages(fees, rewards, slots, depths, [uint256(0), 10, 10, 10, 10, 8]);
        membership.setCycleGuardEnabled(true);
        vm.stopPrank();

        for (uint256 i; i < WALLET_COUNT; i++) {
            uint256 funding;
            for (uint256 stageId; stageId <= terminalStage[wallets[i]]; stageId++) {
                funding += fees[stageId];
            }
            vm.prank(ADMIN);
            token.mint(wallets[i], funding);
            vm.prank(wallets[i]);
            token.approve(address(membership), type(uint256).max);
        }
    }

    function test_350Wallets_SixCohorts_DistinctStageRoots_OneTreasury() public {
        vm.pauseGasMetering();

        uint256[6] memory participantCounts;
        uint256[6] memory paidCounts;
        uint256[6] memory stageFees;
        uint256[6] memory stagePool;
        uint256[6] memory stageTreasury;
        uint256[6] memory rootRollovers;
        uint256[6] memory spillovers;
        uint256[6] memory spillunderEarners;

        _runStageZero(participantCounts, paidCounts, stageFees, stagePool, stageTreasury, spillovers);
        _runHigherStages(participantCounts, paidCounts, stageFees, stagePool, stageTreasury, spillovers);

        uint256 expectedFees;
        for (uint256 stageId; stageId < 6; stageId++) {
            BinaryMembershipV1.StageMembership memory rootMem =
                membership.getStageMembership(stageRoots[stageId], stageId);
            rootRollovers[stageId] = rootMem.rolloverCount;

            assertEq(membership.stageAnchor(stageId), stageRoots[stageId], "wrong stage anchor");
            assertEq(rootMem.parent, address(0), "stage root has a parent");
            assertEq(rootRollovers[stageId], paidCounts[stageId] / slots[stageId], "root rollover count");
            assertEq(rootMem.slotsFilledBelow, paidCounts[stageId] % slots[stageId], "root slot remainder");
            assertEq(stageFees[stageId], paidCounts[stageId] * fees[stageId], "stage fee total");
            assertEq(stagePool[stageId] + stageTreasury[stageId], stageFees[stageId], "stage conservation");
            assertGt(spillovers[stageId], 0, "stage did not spill over");
            expectedFees += stageFees[stageId];
        }

        (uint256 stageLedger, uint256 memberLedger) = _auditLedgersAndSpillunder(spillunderEarners);
        assertEq(stageLedger, membership.totalPoolPaid(), "stage earnings mismatch");
        assertEq(memberLedger, membership.totalPoolPaid(), "member earnings mismatch");
        for (uint256 stageId; stageId < 6; stageId++) {
            assertGt(spillunderEarners[stageId], 0, "stage had no spillunder earner");
        }

        assertEq(membership.memberCount(), WALLET_COUNT, "member count");
        assertEq(membership.totalPoolPaid() + membership.totalTreasuryPaid(), expectedFees, "fee conservation");
        assertEq(token.balanceOf(address(membership)), membership.pendingTreasury(), "pre-award insolvency");

        _exerciseReachedAndUnreachedAwards();
        vm.prank(TREASURY);
        membership.withdrawTreasury(UNIT);

        assertEq(token.balanceOf(TREASURY), UNIT, "wrong treasury recipient");
        assertEq(membership.totalAwardsPaid(), 3 * UNIT, "award total");
        assertEq(
            membership.pendingTreasury(),
            membership.totalTreasuryPaid() - 4 * UNIT,
            "pending treasury after awards/withdrawal"
        );
        assertEq(token.balanceOf(address(membership)), membership.pendingTreasury(), "final insolvency");

        _report(
            participantCounts,
            paidCounts,
            stageFees,
            stagePool,
            stageTreasury,
            rootRollovers,
            spillovers,
            spillunderEarners
        );

        vm.resumeGasMetering();
    }

    function _assignWalletsAndCohorts() internal {
        for (uint256 stageId; stageId < 6; stageId++) {
            // Safe because stageId is bounded to six small fixture addresses.
            // forge-lint: disable-next-line(unsafe-typecast)
            stageRoots[stageId] = address(uint160(0x600000 + stageId));
            wallets[stageId] = stageRoots[stageId];
            terminalStage[stageRoots[stageId]] = stageId;
        }

        uint256 cursor = 6;
        for (uint256 stageId; stageId < 6; stageId++) {
            uint256 remaining = cohortSizes[stageId] - 1; // root already assigned
            for (uint256 j; j < remaining; j++) {
                // Safe because cursor is bounded by WALLET_COUNT (350).
                // forge-lint: disable-next-line(unsafe-typecast)
                address wallet = address(uint160(0x610000 + cursor));
                wallets[cursor++] = wallet;
                terminalStage[wallet] = stageId;
            }
        }
        assertEq(cursor, WALLET_COUNT, "cohort assignment did not total 350");
    }

    function _runStageZero(
        uint256[6] memory participantCounts,
        uint256[6] memory paidCounts,
        uint256[6] memory stageFees,
        uint256[6] memory stagePool,
        uint256[6] memory stageTreasury,
        uint256[6] memory spillovers
    ) internal {
        vm.prank(stageRoots[0]);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);
        participantCounts[0] = WALLET_COUNT;

        for (uint256 i = 1; i < WALLET_COUNT; i++) {
            (address parent, BinaryMembershipV1.Side side) = membership.findPlacementSlot(stageRoots[0], 0);
            if (i <= 2) assertEq(parent, stageRoots[0], "stage 1 first line not under root");
            if (parent != stageRoots[0]) spillovers[0]++;
            uint256 expectedPayout = _expectedPayout(parent, 0);
            uint256 poolBefore = membership.totalPoolPaid();

            vm.prank(wallets[i]);
            membership.register(stageRoots[0], parent, side);
            assertEq(membership.totalPoolPaid() - poolBefore, expectedPayout, "stage 1 payout");
        }

        paidCounts[0] = WALLET_COUNT - 1;
        stageFees[0] = paidCounts[0] * fees[0];
        stagePool[0] = membership.totalPoolPaid();
        stageTreasury[0] = membership.totalTreasuryPaid();
    }

    function _runHigherStages(
        uint256[6] memory participantCounts,
        uint256[6] memory paidCounts,
        uint256[6] memory stageFees,
        uint256[6] memory stagePool,
        uint256[6] memory stageTreasury,
        uint256[6] memory spillovers
    ) internal {
        for (uint256 stageId = 1; stageId < 6; stageId++) {
            vm.prank(OPERATOR);
            membership.enrollStageRoot(stageRoots[stageId], stageId);

            uint256 poolBefore = membership.totalPoolPaid();
            uint256 treasuryBefore = membership.totalTreasuryPaid();
            uint256 joined;

            for (uint256 i; i < WALLET_COUNT; i++) {
                address wallet = wallets[i];
                if (wallet == stageRoots[stageId] || terminalStage[wallet] < stageId) continue;

                (address parent, BinaryMembershipV1.Side side) =
                    membership.findPlacementSlot(stageRoots[stageId], stageId);
                if (joined < 2) assertEq(parent, stageRoots[stageId], "first line not under stage root");
                if (parent != stageRoots[stageId]) spillovers[stageId]++;
                uint256 expectedPayout = _expectedPayout(parent, stageId);
                uint256 joinPoolBefore = membership.totalPoolPaid();

                vm.prank(wallet);
                membership.joinStage(stageId, parent, side);
                assertEq(membership.totalPoolPaid() - joinPoolBefore, expectedPayout, "higher-stage payout");
                joined++;
            }

            participantCounts[stageId] = joined + 1;
            paidCounts[stageId] = joined;
            stageFees[stageId] = joined * fees[stageId];
            stagePool[stageId] = membership.totalPoolPaid() - poolBefore;
            stageTreasury[stageId] = membership.totalTreasuryPaid() - treasuryBefore;
        }
    }

    function _auditLedgersAndSpillunder(uint256[6] memory spillunderEarners)
        internal
        view
        returns (uint256 stageLedger, uint256 memberLedger)
    {
        for (uint256 i; i < WALLET_COUNT; i++) {
            address wallet = wallets[i];
            uint256 aggregate;
            for (uint256 stageId; stageId <= terminalStage[wallet]; stageId++) {
                BinaryMembershipV1.StageMembership memory mem = membership.getStageMembership(wallet, stageId);
                assertTrue(mem.enrolled, "wallet missing prerequisite stage");
                assertLt(mem.slotsFilledBelow, slots[stageId], "slot count escaped board");
                aggregate += mem.stageEarnings;
                stageLedger += mem.stageEarnings;

                // Only stageRoots[0] sponsored registrations. Any other wallet
                // earning is a placement-based spillunder beneficiary.
                if (wallet != stageRoots[0] && mem.stageEarnings > 0) {
                    spillunderEarners[stageId]++;
                }
            }
            assertEq(membership.getMember(wallet).totalEarned, aggregate, "wallet aggregate mismatch");
            memberLedger += aggregate;
        }
    }

    function _exerciseReachedAndUnreachedAwards() internal {
        for (uint256 stageId = 1; stageId <= 3; stageId++) {
            (,,, uint256 milestone, bool eligible) = membership.getAwardInfo(stageRoots[stageId], stageId);
            assertEq(milestone, 10, "wrong ten-rollover milestone");
            assertTrue(eligible, "eligible stage root rejected");
            vm.prank(OPERATOR);
            membership.grantPhysicalAward(stageRoots[stageId], stageId, UNIT);
        }

        BinaryMembershipV1.StageMembership memory stageFiveRoot = membership.getStageMembership(stageRoots[4], 4);
        vm.expectRevert(
            abi.encodeWithSelector(BinaryMembershipV1.RolloversNotMet.selector, 10, stageFiveRoot.rolloverCount)
        );
        vm.prank(OPERATOR);
        membership.grantPhysicalAward(stageRoots[4], 4, UNIT);

        BinaryMembershipV1.StageMembership memory stageSixRoot = membership.getStageMembership(stageRoots[5], 5);
        vm.expectRevert(
            abi.encodeWithSelector(BinaryMembershipV1.RolloversNotMet.selector, 8, stageSixRoot.rolloverCount)
        );
        vm.prank(OPERATOR);
        membership.grantPhysicalAward(stageRoots[5], 5, UNIT);
    }

    function _expectedPayout(address parent, uint256 stageId) internal view returns (uint256 payout) {
        address current = parent;
        for (uint256 level; level < depths[stageId] && current != address(0); level++) {
            payout += rewards[stageId];
            BinaryMembershipV1.StageMembership memory mem = membership.getStageMembership(current, stageId);
            address par = mem.parent;
            if (par == address(0)) break;
            BinaryMembershipV1.StageMembership memory parMem = membership.getStageMembership(par, stageId);
            if (parMem.left != current && parMem.right != current) break;
            current = par;
        }
    }

    function _report(
        uint256[6] memory participantCounts,
        uint256[6] memory paidCounts,
        uint256[6] memory stageFees,
        uint256[6] memory stagePool,
        uint256[6] memory stageTreasury,
        uint256[6] memory rootRollovers,
        uint256[6] memory spillovers,
        uint256[6] memory spillunderEarners
    ) internal view {
        console.log("=== 350 WALLETS / SIX COHORTS / SIX ROOTS ===");
        console.log("one global treasury        :", TREASURY);
        for (uint256 stageId; stageId < 6; stageId++) {
            console.log("stage", stageId + 1);
            console.log("  distinct root            :", stageRoots[stageId]);
            console.log("  terminal cohort size     :", cohortSizes[stageId]);
            console.log("  participants incl root   :", participantCounts[stageId]);
            console.log("  paid joins               :", paidCounts[stageId]);
            console.log("  fees                     :", stageFees[stageId] / UNIT);
            console.log("  node rewards             :", stagePool[stageId] / UNIT);
            console.log("  gross treasury           :", stageTreasury[stageId] / UNIT);
            console.log("  root rollovers           :", rootRollovers[stageId]);
            console.log("  spillover placements     :", spillovers[stageId]);
            console.log("  spillunder earners       :", spillunderEarners[stageId]);
        }
        console.log(
            "fees collected             :", (membership.totalPoolPaid() + membership.totalTreasuryPaid()) / UNIT
        );
        console.log("node rewards               :", membership.totalPoolPaid() / UNIT);
        console.log("gross treasury             :", membership.totalTreasuryPaid() / UNIT);
        console.log("awards paid                :", membership.totalAwardsPaid() / UNIT);
        console.log("treasury withdrawn         :", token.balanceOf(TREASURY) / UNIT);
        console.log("pending treasury           :", membership.pendingTreasury() / UNIT);
        console.log("contract balance           :", token.balanceOf(address(membership)) / UNIT);
    }
}
