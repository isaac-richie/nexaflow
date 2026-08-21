// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {MockUSDT18} from "../src/MockUSDT18.sol";

/// @notice Dedicated 350-wallet, one-treasury campaign requested for the
///         production configuration. Every paying wallet traverses all six
///         stages while sponsor-first spillover, anchor fallback, spillunder,
///         rollovers, physical awards and a treasury withdrawal are reconciled.
contract BinaryMembershipV1Stress350TreasuryTest is Test {
    uint256 internal constant UNIT = 1e18;
    uint256 internal constant WALLET_COUNT = 350; // root + 349 paying wallets
    uint256 internal constant PAYING_COUNT = WALLET_COUNT - 1;

    address internal constant ADMIN = address(0xAD);
    address internal constant OPERATOR = address(0x0B);
    address internal constant TREASURY = address(0x7EA5);
    address internal constant ROOT = address(0x1);

    MockUSDT18 internal token;
    BinaryMembershipV1 internal membership;
    address[PAYING_COUNT] internal wallets;
    address[PAYING_COUNT] internal sponsors;
    uint256[WALLET_COUNT] internal sponsorCounts;

    uint256[6] internal fees = [uint256(20 * UNIT), 60 * UNIT, 180 * UNIT, 540 * UNIT, 1_620 * UNIT, 4_860 * UNIT];
    uint256[6] internal rewards = [uint256(5 * UNIT), 10 * UNIT, 25 * UNIT, 80 * UNIT, 250 * UNIT, 800 * UNIT];
    uint256[6] internal slots = [uint256(6), 14, 14, 14, 14, 14];
    uint256[6] internal depths = [uint256(2), 3, 3, 3, 3, 3];

    function setUp() public {
        token = new MockUSDT18(ADMIN);

        vm.startPrank(ADMIN);
        membership = new BinaryMembershipV1(IERC20(address(token)), TREASURY, ADMIN, uint48(2 days), ROOT);
        membership.grantRole(membership.OPERATOR_ROLE(), OPERATOR);
        membership.grantRole(membership.TREASURY_ROLE(), TREASURY);
        membership.configureStages(fees, rewards, slots, depths, [uint256(0), 10, 10, 10, 10, 8]);
        membership.setCycleGuardEnabled(true);
        vm.stopPrank();

        vm.prank(ROOT);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);

        uint256 perWalletFunding;
        for (uint256 stageId; stageId < 6; stageId++) {
            perWalletFunding += fees[stageId];
        }

        for (uint256 i; i < PAYING_COUNT; i++) {
            // Safe because i is bounded by PAYING_COUNT (349).
            // forge-lint: disable-next-line(unsafe-typecast)
            address wallet = address(uint160(0x350000 + i));
            wallets[i] = wallet;

            vm.prank(ADMIN);
            token.mint(wallet, perWalletFunding);
            vm.prank(wallet);
            token.approve(address(membership), type(uint256).max);
        }
    }

    function test_350Wallets_AllStages_SpilloverSpillunderRolloverAndTreasury() public {
        // This is one synthetic Foundry transaction containing 2,094 real-life
        // joins. Dedicated gas tests cover each individual bounded operation.
        vm.pauseGasMetering();

        uint256[6] memory stageFees;
        uint256[6] memory stagePool;
        uint256[6] memory stageTreasury;
        uint256[6] memory spillovers;
        uint256[6] memory anchorFallbacks;

        _registerAll(stageFees, stagePool, stageTreasury, spillovers, anchorFallbacks);
        _joinHigherStages(stageFees, stagePool, stageTreasury, spillovers, anchorFallbacks);

        assertEq(membership.memberCount(), WALLET_COUNT, "wallet count mismatch");

        uint256 expectedFees;
        for (uint256 stageId; stageId < 6; stageId++) {
            uint256 expectedStageFees = PAYING_COUNT * fees[stageId];
            assertEq(stageFees[stageId], expectedStageFees, "stage fee mismatch");
            assertEq(stagePool[stageId] + stageTreasury[stageId], expectedStageFees, "stage conservation");
            assertGt(spillovers[stageId], 0, "stage did not exercise spillover");
            expectedFees += expectedStageFees;
        }

        assertEq(membership.totalPoolPaid() + membership.totalTreasuryPaid(), expectedFees, "fee conservation");
        assertEq(token.balanceOf(address(membership)), membership.pendingTreasury(), "pre-award insolvency");

        (
            uint256[6] memory totalRollovers,
            uint256[6] memory spillunderEarners,
            uint256 stageLedger,
            uint256 memberLedger
        ) = _auditMemberState();
        assertEq(stageLedger, membership.totalPoolPaid(), "stage earnings do not reconcile");
        assertEq(memberLedger, membership.totalPoolPaid(), "member earnings do not reconcile");
        for (uint256 stageId; stageId < 6; stageId++) {
            assertGt(totalRollovers[stageId], 0, "stage did not roll over");
            assertGt(spillunderEarners[stageId], 0, "stage produced no spillunder earner");
        }

        _exerciseAwardsAndTreasury(expectedFees);
        _report(
            expectedFees,
            stageFees,
            stagePool,
            stageTreasury,
            spillovers,
            anchorFallbacks,
            totalRollovers,
            spillunderEarners
        );

        vm.resumeGasMetering();
    }

    function _registerAll(
        uint256[6] memory stageFees,
        uint256[6] memory stagePool,
        uint256[6] memory stageTreasury,
        uint256[6] memory spillovers,
        uint256[6] memory anchorFallbacks
    ) internal {
        uint256 poolBefore = membership.totalPoolPaid();
        uint256 treasuryBefore = membership.totalTreasuryPaid();

        for (uint256 i; i < PAYING_COUNT; i++) {
            address sponsor = _chooseSponsor(i);
            sponsors[i] = sponsor;
            sponsorCounts[_bucket(sponsor)]++;

            (address parent, BinaryMembershipV1.Side side) = membership.findPlacementSlot(sponsor, 0);
            if (parent != sponsor) spillovers[0]++;
            if (!_isAtOrBelow(parent, sponsor, 0)) anchorFallbacks[0]++;

            uint256 expectedPayout = _expectedPayout(parent, 0);
            uint256 joinPoolBefore = membership.totalPoolPaid();
            vm.prank(wallets[i]);
            membership.register(sponsor, parent, side);
            assertEq(membership.totalPoolPaid() - joinPoolBefore, expectedPayout, "stage 1 payout path");
        }

        stageFees[0] = PAYING_COUNT * fees[0];
        stagePool[0] = membership.totalPoolPaid() - poolBefore;
        stageTreasury[0] = membership.totalTreasuryPaid() - treasuryBefore;
    }

    function _joinHigherStages(
        uint256[6] memory stageFees,
        uint256[6] memory stagePool,
        uint256[6] memory stageTreasury,
        uint256[6] memory spillovers,
        uint256[6] memory anchorFallbacks
    ) internal {
        for (uint256 stageId = 1; stageId < 6; stageId++) {
            vm.prank(OPERATOR);
            membership.enrollStageRoot(ROOT, stageId);

            uint256 poolBefore = membership.totalPoolPaid();
            uint256 treasuryBefore = membership.totalTreasuryPaid();

            for (uint256 i; i < PAYING_COUNT; i++) {
                address sponsor = sponsors[i];
                (address parent, BinaryMembershipV1.Side side) = membership.findPlacementSlot(sponsor, stageId);
                if (parent != sponsor) spillovers[stageId]++;
                if (!_isAtOrBelow(parent, sponsor, stageId)) anchorFallbacks[stageId]++;

                uint256 expectedPayout = _expectedPayout(parent, stageId);
                uint256 joinPoolBefore = membership.totalPoolPaid();
                vm.prank(wallets[i]);
                membership.joinStage(stageId, parent, side);
                assertEq(membership.totalPoolPaid() - joinPoolBefore, expectedPayout, "higher-stage payout path");
            }

            stageFees[stageId] = PAYING_COUNT * fees[stageId];
            stagePool[stageId] = membership.totalPoolPaid() - poolBefore;
            stageTreasury[stageId] = membership.totalTreasuryPaid() - treasuryBefore;
        }
    }

    function _auditMemberState()
        internal
        view
        returns (
            uint256[6] memory totalRollovers,
            uint256[6] memory spillunderEarners,
            uint256 stageLedger,
            uint256 memberLedger
        )
    {
        uint256 rootAggregate;
        for (uint256 stageId; stageId < 6; stageId++) {
            BinaryMembershipV1.StageMembership memory rootMem = membership.getStageMembership(ROOT, stageId);
            stageLedger += rootMem.stageEarnings;
            rootAggregate += rootMem.stageEarnings;
            totalRollovers[stageId] += rootMem.rolloverCount;
        }
        assertEq(membership.getMember(ROOT).totalEarned, rootAggregate, "root ledger mismatch");
        memberLedger += rootAggregate;

        for (uint256 i; i < PAYING_COUNT; i++) {
            uint256 aggregate;
            for (uint256 stageId; stageId < 6; stageId++) {
                BinaryMembershipV1.StageMembership memory mem = membership.getStageMembership(wallets[i], stageId);
                assertTrue(mem.enrolled, "wallet missing stage");
                assertLt(mem.slotsFilledBelow, slots[stageId], "slot counter escaped board");
                aggregate += mem.stageEarnings;
                stageLedger += mem.stageEarnings;
                totalRollovers[stageId] += mem.rolloverCount;
                if (sponsorCounts[i + 1] == 0 && mem.stageEarnings > 0) {
                    spillunderEarners[stageId]++;
                }
            }
            assertEq(membership.getMember(wallets[i]).totalEarned, aggregate, "wallet ledger mismatch");
            memberLedger += aggregate;
        }
    }

    function _exerciseAwardsAndTreasury(uint256 expectedFees) internal {
        uint256 rootBalanceBeforeAwards = token.balanceOf(ROOT);
        for (uint256 stageId = 1; stageId < 6; stageId++) {
            (,,, uint256 milestone, bool eligible) = membership.getAwardInfo(ROOT, stageId);
            assertEq(milestone, stageId == 5 ? 8 : 10, "wrong award milestone");
            assertTrue(eligible, "root did not reach award milestone");
            vm.prank(OPERATOR);
            membership.grantPhysicalAward(ROOT, stageId, UNIT);
        }

        assertEq(membership.totalAwardsPaid(), 5 * UNIT, "award accounting");
        assertEq(token.balanceOf(ROOT) - rootBalanceBeforeAwards, 5 * UNIT, "root award balance delta");

        vm.prank(TREASURY);
        membership.withdrawTreasury(UNIT);
        assertEq(token.balanceOf(TREASURY), UNIT, "treasury withdrawal destination");
        assertEq(
            membership.pendingTreasury(),
            membership.totalTreasuryPaid() - 6 * UNIT,
            "pending treasury after awards/withdrawal"
        );
        assertEq(token.balanceOf(address(membership)), membership.pendingTreasury(), "final treasury insolvency");
        assertEq(membership.totalPoolPaid() + membership.totalTreasuryPaid(), expectedFees, "post-action conservation");
    }

    function _chooseSponsor(uint256 index) internal view returns (address) {
        // The first 140 paid members concentrate beneath ROOT so every award
        // boundary is crossed. The remaining 209 use deterministic earlier
        // sponsors, spreading later placements into ordinary members' boards.
        if (index < 140) return ROOT;
        uint256 sponsorIndex = uint256(keccak256(abi.encodePacked("STRESS-350", index))) % index;
        return wallets[sponsorIndex];
    }

    function _bucket(address member) internal view returns (uint256) {
        if (member == ROOT) return 0;
        for (uint256 i; i < PAYING_COUNT; i++) {
            if (wallets[i] == member) return i + 1;
        }
        revert("unknown sponsor");
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

    function _isAtOrBelow(address node, address ancestor, uint256 stageId) internal view returns (bool) {
        address current = node;
        for (uint256 links; links < 64 && current != address(0); links++) {
            if (current == ancestor) return true;
            current = membership.getStageMembership(current, stageId).parent;
        }
        return false;
    }

    function _report(
        uint256 expectedFees,
        uint256[6] memory stageFees,
        uint256[6] memory stagePool,
        uint256[6] memory stageTreasury,
        uint256[6] memory spillovers,
        uint256[6] memory anchorFallbacks,
        uint256[6] memory totalRollovers,
        uint256[6] memory spillunderEarners
    ) internal view {
        console.log("=== 350-WALLET / ONE-TREASURY CAMPAIGN ===");
        console.log("member wallets             :", WALLET_COUNT);
        console.log("paying wallets             :", PAYING_COUNT);
        console.log("paid placements            :", PAYING_COUNT * 6);
        for (uint256 stageId; stageId < 6; stageId++) {
            console.log("stage", stageId + 1);
            console.log("  fees                     :", stageFees[stageId] / UNIT);
            console.log("  node rewards             :", stagePool[stageId] / UNIT);
            console.log("  gross treasury           :", stageTreasury[stageId] / UNIT);
            console.log("  spillover placements     :", spillovers[stageId]);
            console.log("  anchor fallback placements:", anchorFallbacks[stageId]);
            console.log("  all member rollovers     :", totalRollovers[stageId]);
            console.log("  spillunder earners       :", spillunderEarners[stageId]);
        }
        console.log("fees collected             :", expectedFees / UNIT);
        console.log("node rewards               :", membership.totalPoolPaid() / UNIT);
        console.log("gross treasury             :", membership.totalTreasuryPaid() / UNIT);
        console.log("awards paid                :", membership.totalAwardsPaid() / UNIT);
        console.log("treasury withdrawn         :", token.balanceOf(TREASURY) / UNIT);
        console.log("pending treasury           :", membership.pendingTreasury() / UNIT);
        console.log("contract balance           :", token.balanceOf(address(membership)) / UNIT);
    }
}
