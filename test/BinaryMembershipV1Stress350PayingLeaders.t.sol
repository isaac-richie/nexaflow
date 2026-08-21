// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {MockUSDT18} from "../src/MockUSDT18.sol";

/// @notice Community-language "roots": six distinct ordinary wallets that pay
///         to enter, then receive the first two members beneath them. A single
///         fee-free system anchor only bootstraps placement at each stage.
contract BinaryMembershipV1Stress350PayingLeadersTest is Test {
    uint256 internal constant UNIT = 1e18;
    uint256 internal constant COMMUNITY_WALLETS = 350;

    address internal constant ADMIN = address(0xAD);
    address internal constant OPERATOR = address(0x0B);
    address internal constant TREASURY = address(0x7EA5);
    address internal constant SYSTEM_ANCHOR = address(0xA110);

    MockUSDT18 internal token;
    BinaryMembershipV1 internal membership;
    address[COMMUNITY_WALLETS] internal wallets;
    address[6] internal leaders;
    mapping(address => uint256) internal terminalStage;

    uint256[6] internal cohortSizes = [uint256(59), 59, 58, 58, 58, 58];
    uint256[6] internal fees = [uint256(20 * UNIT), 60 * UNIT, 180 * UNIT, 540 * UNIT, 1_620 * UNIT, 4_860 * UNIT];
    uint256[6] internal rewards = [uint256(5 * UNIT), 10 * UNIT, 25 * UNIT, 80 * UNIT, 250 * UNIT, 800 * UNIT];
    uint256[6] internal slots = [uint256(6), 14, 14, 14, 14, 14];
    uint256[6] internal depths = [uint256(2), 3, 3, 3, 3, 3];

    function setUp() public {
        _assignCohorts();
        token = new MockUSDT18(ADMIN);

        vm.startPrank(ADMIN);
        membership = new BinaryMembershipV1(IERC20(address(token)), TREASURY, ADMIN, uint48(2 days), SYSTEM_ANCHOR);
        membership.grantRole(membership.OPERATOR_ROLE(), OPERATOR);
        membership.grantRole(membership.TREASURY_ROLE(), TREASURY);
        membership.configureStages(fees, rewards, slots, depths, [uint256(0), 10, 10, 10, 10, 8]);
        membership.setCycleGuardEnabled(true);
        vm.stopPrank();

        vm.prank(SYSTEM_ANCHOR);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);

        for (uint256 i; i < COMMUNITY_WALLETS; i++) {
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

    function test_350PayingWallets_DistinctLeaders_FirstTwoAndTreasury() public {
        vm.pauseGasMetering();

        uint256[6] memory paidCounts;
        uint256[6] memory stageFees;
        uint256[6] memory stagePool;
        uint256[6] memory stageTreasury;
        uint256[6] memory placementsOnLeaderBoard;
        uint256[6] memory fallbackPlacements;
        uint256[6] memory leaderRollovers;
        uint256[6] memory anchorRollovers;
        uint256[6] memory leaderEarnings;

        _runStageZero(paidCounts, stageFees, stagePool, stageTreasury, placementsOnLeaderBoard, fallbackPlacements);
        _runHigherStages(paidCounts, stageFees, stagePool, stageTreasury, placementsOnLeaderBoard, fallbackPlacements);

        uint256 expectedFees;
        for (uint256 stageId; stageId < 6; stageId++) {
            BinaryMembershipV1.StageMembership memory leaderMem =
                membership.getStageMembership(leaders[stageId], stageId);
            BinaryMembershipV1.StageMembership memory anchorMem = membership.getStageMembership(SYSTEM_ANCHOR, stageId);
            leaderRollovers[stageId] = leaderMem.rolloverCount;
            anchorRollovers[stageId] = anchorMem.rolloverCount;
            leaderEarnings[stageId] = leaderMem.stageEarnings;

            assertTrue(leaderMem.parent != address(0), "paying leader incorrectly became fee-free root");
            assertEq(stageFees[stageId], paidCounts[stageId] * fees[stageId], "stage fees");
            assertEq(stagePool[stageId] + stageTreasury[stageId], stageFees[stageId], "stage conservation");
            expectedFees += stageFees[stageId];
        }

        _assertLeaderContinuity(
            paidCounts,
            placementsOnLeaderBoard,
            fallbackPlacements,
            leaderRollovers,
            anchorRollovers
        );

        assertEq(membership.memberCount(), COMMUNITY_WALLETS + 1, "member count incl system anchor");
        assertEq(membership.totalPoolPaid() + membership.totalTreasuryPaid(), expectedFees, "fee conservation");
        assertEq(token.balanceOf(address(membership)), membership.pendingTreasury(), "pre-withdraw insolvency");

        // Ordinary paying leaders now keep cycling after their ancestor drops
        // the historical link. This campaign reaches the 10-rollover award at
        // stages 2-4, while the two smaller cohorts remain below threshold.
        for (uint256 stageId = 1; stageId <= 3; stageId++) {
            uint256 threshold = stageId == 5 ? 8 : 10;
            (,,, uint256 milestone, bool eligible) = membership.getAwardInfo(leaders[stageId], stageId);
            assertEq(milestone, threshold, "wrong leader award milestone");
            assertTrue(eligible, "paying leader did not reach award threshold");
            vm.prank(OPERATOR);
            membership.grantPhysicalAward(leaders[stageId], stageId, UNIT);
        }
        for (uint256 stageId = 4; stageId < 6; stageId++) {
            uint256 threshold = stageId == 5 ? 8 : 10;
            (,,, uint256 milestone, bool eligible) = membership.getAwardInfo(leaders[stageId], stageId);
            assertEq(milestone, threshold, "wrong leader award milestone");
            assertFalse(eligible, "sub-threshold leader became award eligible");
        }

        vm.prank(TREASURY);
        membership.withdrawTreasury(UNIT);
        assertEq(token.balanceOf(TREASURY), UNIT, "single treasury did not receive withdrawal");
        assertEq(membership.totalAwardsPaid(), 3 * UNIT, "award total");
        assertEq(membership.pendingTreasury(), membership.totalTreasuryPaid() - 4 * UNIT, "pending treasury");
        assertEq(token.balanceOf(address(membership)), membership.pendingTreasury(), "final insolvency");

        _report(
            paidCounts,
            stageFees,
            stagePool,
            stageTreasury,
            placementsOnLeaderBoard,
            fallbackPlacements,
            leaderRollovers,
            anchorRollovers,
            leaderEarnings
        );

        vm.resumeGasMetering();
    }

    function _assertLeaderContinuity(
        uint256[6] memory paidCounts,
        uint256[6] memory placementsOnLeaderBoard,
        uint256[6] memory fallbackPlacements,
        uint256[6] memory leaderRollovers,
        uint256[6] memory anchorRollovers
    ) internal view {
        for (uint256 stageId; stageId < 6; stageId++) {
            assertEq(
                placementsOnLeaderBoard[stageId],
                paidCounts[stageId] - 1,
                "followers escaped paying leader's board"
            );
            assertEq(fallbackPlacements[stageId], 0, "finder abandoned a detached paying leader");
            assertEq(
                leaderRollovers[stageId],
                (paidCounts[stageId] - 1) / slots[stageId],
                "paying leader did not keep cycling"
            );
            // The first complete board is shared while the leader is still a
            // live child of the anchor. Once that rollover detaches the edge,
            // all later leader cycles must stop at the new board boundary.
            assertEq(anchorRollovers[stageId], 1, "detached board kept crediting technical anchor");
        }
    }

    function _assignCohorts() internal {
        for (uint256 stageId; stageId < 6; stageId++) {
            // Safe because stageId is bounded to six fixture addresses.
            // forge-lint: disable-next-line(unsafe-typecast)
            leaders[stageId] = address(uint160(0x700000 + stageId));
            wallets[stageId] = leaders[stageId];
            terminalStage[leaders[stageId]] = stageId;
        }

        uint256 cursor = 6;
        for (uint256 stageId; stageId < 6; stageId++) {
            for (uint256 j; j < cohortSizes[stageId] - 1; j++) {
                // Safe because cursor is bounded by COMMUNITY_WALLETS (350).
                // forge-lint: disable-next-line(unsafe-typecast)
                address wallet = address(uint160(0x710000 + cursor));
                wallets[cursor++] = wallet;
                terminalStage[wallet] = stageId;
            }
        }
        assertEq(cursor, COMMUNITY_WALLETS, "cohorts do not total 350");
    }

    function _runStageZero(
        uint256[6] memory paidCounts,
        uint256[6] memory stageFees,
        uint256[6] memory stagePool,
        uint256[6] memory stageTreasury,
        uint256[6] memory onLeaderBoard,
        uint256[6] memory fallbackPlacements
    ) internal {
        _registerPayingLeader(0);
        uint256 poolBefore = membership.totalPoolPaid();
        uint256 treasuryBefore = membership.totalTreasuryPaid();

        for (uint256 i = 1; i < COMMUNITY_WALLETS; i++) {
            (address parent, BinaryMembershipV1.Side side) = membership.findPlacementSlot(leaders[0], 0);
            if (i <= 2) assertEq(parent, leaders[0], "stage 1 leader did not receive first two");
            if (_isAtOrBelow(parent, leaders[0], 0)) onLeaderBoard[0]++;
            else fallbackPlacements[0]++;

            vm.prank(wallets[i]);
            membership.register(SYSTEM_ANCHOR, parent, side);
        }

        paidCounts[0] = COMMUNITY_WALLETS;
        stageFees[0] = paidCounts[0] * fees[0];
        stagePool[0] = membership.totalPoolPaid();
        stageTreasury[0] = membership.totalTreasuryPaid();
        assertGt(stagePool[0] - poolBefore, 0, "followers paid no stage 1 rewards");
        assertGt(stageTreasury[0] - treasuryBefore, 0, "followers paid no stage 1 treasury");
    }

    function _registerPayingLeader(uint256 stageId) internal {
        (address parent, BinaryMembershipV1.Side side) = membership.findPlacementSlot(SYSTEM_ANCHOR, stageId);
        if (stageId == 0) {
            vm.prank(leaders[stageId]);
            membership.register(SYSTEM_ANCHOR, parent, side);
        } else {
            vm.prank(leaders[stageId]);
            membership.joinStage(stageId, parent, side);
        }
    }

    function _runHigherStages(
        uint256[6] memory paidCounts,
        uint256[6] memory stageFees,
        uint256[6] memory stagePool,
        uint256[6] memory stageTreasury,
        uint256[6] memory onLeaderBoard,
        uint256[6] memory fallbackPlacements
    ) internal {
        for (uint256 stageId = 1; stageId < 6; stageId++) {
            vm.prank(OPERATOR);
            membership.enrollStageRoot(SYSTEM_ANCHOR, stageId);

            uint256 poolBefore = membership.totalPoolPaid();
            uint256 treasuryBefore = membership.totalTreasuryPaid();
            _registerPayingLeader(stageId);
            uint256 joined = 1;

            for (uint256 i; i < COMMUNITY_WALLETS; i++) {
                address wallet = wallets[i];
                if (wallet == leaders[stageId] || terminalStage[wallet] < stageId) continue;

                (address parent, BinaryMembershipV1.Side side) = membership.findPlacementSlot(leaders[stageId], stageId);
                if (joined <= 2) assertEq(parent, leaders[stageId], "leader did not receive first two");
                if (_isAtOrBelow(parent, leaders[stageId], stageId)) onLeaderBoard[stageId]++;
                else fallbackPlacements[stageId]++;

                vm.prank(wallet);
                membership.joinStage(stageId, parent, side);
                joined++;
            }

            paidCounts[stageId] = joined;
            stageFees[stageId] = joined * fees[stageId];
            stagePool[stageId] = membership.totalPoolPaid() - poolBefore;
            stageTreasury[stageId] = membership.totalTreasuryPaid() - treasuryBefore;
        }
    }

    function _isAtOrBelow(address node, address ancestor, uint256 stageId) internal view returns (bool) {
        address current = node;
        for (uint256 links; links < 64 && current != address(0); links++) {
            if (current == ancestor) return true;
            current = membership.getStageMembership(current, stageId).parent;
        }
        return false;
    }

    function _report(
        uint256[6] memory paidCounts,
        uint256[6] memory stageFees,
        uint256[6] memory stagePool,
        uint256[6] memory stageTreasury,
        uint256[6] memory onLeaderBoard,
        uint256[6] memory fallbackPlacements,
        uint256[6] memory leaderRollovers,
        uint256[6] memory anchorRollovers,
        uint256[6] memory leaderEarnings
    ) internal view {
        console.log("=== 350 PAYING WALLETS / SIX PAYING LEADERS ===");
        console.log("technical system anchor    :", SYSTEM_ANCHOR);
        console.log("one global treasury        :", TREASURY);
        for (uint256 stageId; stageId < 6; stageId++) {
            console.log("stage", stageId + 1);
            console.log("  paying board leader      :", leaders[stageId]);
            console.log("  terminal cohort size     :", cohortSizes[stageId]);
            console.log("  paid joins               :", paidCounts[stageId]);
            console.log("  fees                     :", stageFees[stageId] / UNIT);
            console.log("  node rewards             :", stagePool[stageId] / UNIT);
            console.log("  gross treasury           :", stageTreasury[stageId] / UNIT);
            console.log("  placements on leader board:", onLeaderBoard[stageId]);
            console.log("  fallback after detachment:", fallbackPlacements[stageId]);
            console.log("  leader rollovers         :", leaderRollovers[stageId]);
            console.log("  technical anchor rollovers:", anchorRollovers[stageId]);
            console.log("  leader earnings          :", leaderEarnings[stageId] / UNIT);
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
