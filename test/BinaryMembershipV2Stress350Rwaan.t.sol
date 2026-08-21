// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {BinaryMembershipV2} from "../src/BinaryMembershipV2.sol";
import {MockAssetUsdPriceOracle} from "../src/MockAssetUsdPriceOracle.sol";
import {MockRWAAN18} from "../src/MockRWAAN18.sol";

/// @notice Aggressive RWAAN-priced campaigns covering 350 and 500 wallets
///         across stages 0-4. Prices move on every paid entry while fee
///         conservation, treasury solvency, rollovers, spillover and
///         spillunder reconcile.
contract BinaryMembershipV2Stress350RwaanTest is Test {
    uint256 internal constant UNIT = 1e18;
    uint256 internal constant STAGE_COUNT = 5;
    uint256 internal constant MAX_WALLET_COUNT = 500;
    uint256 internal constant MAX_PAYING_COUNT = MAX_WALLET_COUNT - 1;

    address internal constant ADMIN = address(0xAD);
    address internal constant OPERATOR = address(0x0B);
    address internal constant TREASURY = address(0x7EA5);
    address internal constant COMPANY = address(0xC0);
    address internal constant ROOT = address(0x1);

    MockRWAAN18 internal rwaan;
    MockAssetUsdPriceOracle internal oracle;
    BinaryMembershipV2 internal membership;

    address[MAX_PAYING_COUNT] internal wallets;
    address[MAX_PAYING_COUNT] internal sponsors;
    uint256[MAX_WALLET_COUNT] internal sponsorCounts;
    uint256 internal campaignWalletCount;
    uint256 internal payingCount;

    uint256[6] internal usdFees = [uint256(20 * UNIT), 60 * UNIT, 180 * UNIT, 540 * UNIT, 1_620 * UNIT, 4_860 * UNIT];
    uint256[6] internal usdRewards = [uint256(5 * UNIT), 10 * UNIT, 25 * UNIT, 80 * UNIT, 250 * UNIT, 800 * UNIT];
    uint256[6] internal slots = [uint256(6), 14, 14, 14, 14, 14];
    uint256[6] internal depths = [uint256(2), 3, 3, 3, 3, 3];
    uint256[6] internal prices =
        [uint256(0.00005 ether), 0.0000725 ether, 0.0001 ether, 0.0002 ether, 0.01 ether, 3 ether];

    uint256[6] internal stageFeesCollected;
    uint256[6] internal stagePoolPaid;
    uint256[6] internal stageTreasuryPaid;
    uint256[6] internal spillovers;
    uint256[6] internal totalRollovers;
    uint256[6] internal spillunderEarners;
    uint256[6] internal minQuotedFee;
    uint256[6] internal maxQuotedFee;
    uint256 internal rejectedMovedPriceQuotes;

    function setUp() public {
        vm.warp(30 days);
        rwaan = new MockRWAAN18(ADMIN);
        oracle = new MockAssetUsdPriceOracle(prices[0]);
        membership =
            new BinaryMembershipV2(IERC20Metadata(address(rwaan)), oracle, 2 hours, TREASURY, COMPANY, ADMIN, 0, ROOT);

        vm.startPrank(ADMIN);
        membership.grantRole(membership.OPERATOR_ROLE(), OPERATOR);
        membership.grantRole(membership.TREASURY_ROLE(), TREASURY);
        membership.configureStages(usdFees, usdRewards, slots, depths, [uint256(0), 10, 10, 10, 10, 8]);
        membership.setCycleGuardEnabled(true);
        vm.stopPrank();

        vm.prank(ROOT);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);

        for (uint256 i; i < MAX_PAYING_COUNT; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            address wallet = address(uint160(0x350000 + i));
            wallets[i] = wallet;

            vm.prank(ADMIN);
            rwaan.mint(wallet, 100_000_000 * UNIT);
            vm.prank(wallet);
            rwaan.approve(address(membership), type(uint256).max);
        }
    }

    function test_350Wallets_FiveStages_DynamicRwaan_TreasuryRolloverSpilloverAndSpillunder() public {
        _runCampaign(350);
    }

    function test_500Wallets_FiveStages_DynamicRwaan_TreasuryRolloverSpilloverAndSpillunder() public {
        _runCampaign(500);
    }

    function _runCampaign(uint256 walletCount) internal {
        campaignWalletCount = walletCount;
        payingCount = walletCount - 1;

        // Each synthetic transaction executes every paid join plus adversarial
        // quote reverts. Per-operation gas bounds are covered elsewhere.
        vm.pauseGasMetering();

        _registerAll();
        _joinStagesOneToFour();

        assertEq(membership.memberCount(), campaignWalletCount, "wallet count mismatch");

        uint256 expectedFees;
        for (uint256 stageId; stageId < STAGE_COUNT; stageId++) {
            assertEq(
                stagePoolPaid[stageId] + stageTreasuryPaid[stageId],
                stageFeesCollected[stageId],
                "stage fee conservation"
            );
            assertGt(spillovers[stageId], 0, "stage did not exercise spillover");
            assertLt(minQuotedFee[stageId], maxQuotedFee[stageId], "stage price did not move");
            expectedFees += stageFeesCollected[stageId];
        }

        uint256 expectedRejectedQuotes = ((payingCount + 96) / 97) * STAGE_COUNT;
        assertEq(rejectedMovedPriceQuotes, expectedRejectedQuotes, "wrong moved-price revert count");
        assertEq(membership.totalPoolPaid() + membership.totalTreasuryPaid(), expectedFees, "global fee conservation");
        assertEq(rwaan.balanceOf(address(membership)), membership.pendingTreasury(), "pre-action treasury insolvency");

        (uint256 stageLedger, uint256 memberLedger) = _auditMemberState();
        assertEq(stageLedger, membership.totalPoolPaid(), "stage earnings do not reconcile");
        assertEq(memberLedger, membership.totalPoolPaid(), "member earnings do not reconcile");
        for (uint256 stageId; stageId < STAGE_COUNT; stageId++) {
            assertGt(totalRollovers[stageId], 0, "stage did not roll over");
            assertGt(spillunderEarners[stageId], 0, "stage produced no spillunder earner");
        }

        _exerciseAwardsAndTreasury(expectedFees);
        _report(expectedFees);
        vm.resumeGasMetering();
    }

    function _registerAll() internal {
        uint256 poolBefore = membership.totalPoolPaid();
        uint256 treasuryBefore = membership.totalTreasuryPaid();

        for (uint256 i; i < payingCount; i++) {
            address sponsor = _chooseSponsor(i);
            sponsors[i] = sponsor;
            sponsorCounts[_bucket(sponsor)]++;

            (address parent, BinaryMembershipV1.Side side) = membership.findPlacementSlot(sponsor, 0);
            if (parent != sponsor) spillovers[0]++;

            if (i % 97 == 0) {
                _expectMovedPriceRevert(wallets[i], sponsor, parent, side, 0);
            }
            _payAtMovingPrice(wallets[i], sponsor, parent, side, 0, i);
        }

        stagePoolPaid[0] = membership.totalPoolPaid() - poolBefore;
        stageTreasuryPaid[0] = membership.totalTreasuryPaid() - treasuryBefore;
    }

    function _joinStagesOneToFour() internal {
        for (uint256 stageId = 1; stageId < STAGE_COUNT; stageId++) {
            vm.prank(OPERATOR);
            membership.enrollStageRoot(ROOT, stageId);

            uint256 poolBefore = membership.totalPoolPaid();
            uint256 treasuryBefore = membership.totalTreasuryPaid();

            for (uint256 i; i < payingCount; i++) {
                address sponsor = sponsors[i];
                (address parent, BinaryMembershipV1.Side side) = membership.findPlacementSlot(sponsor, stageId);
                if (parent != sponsor) spillovers[stageId]++;

                if (i % 97 == 0) {
                    _expectMovedPriceRevert(wallets[i], sponsor, parent, side, stageId);
                }
                _payAtMovingPrice(wallets[i], sponsor, parent, side, stageId, i);
            }

            stagePoolPaid[stageId] = membership.totalPoolPaid() - poolBefore;
            stageTreasuryPaid[stageId] = membership.totalTreasuryPaid() - treasuryBefore;
        }
    }

    function _payAtMovingPrice(
        address wallet,
        address sponsor,
        address parent,
        BinaryMembershipV1.Side side,
        uint256 stageId,
        uint256 walletIndex
    ) internal {
        oracle.setPrice(prices[(walletIndex * 7 + stageId * 11) % prices.length]);
        (uint256 feeAmount, uint256 rewardAmount,,) = membership.quoteStagePayment(stageId);
        _trackQuote(stageId, feeAmount);

        uint256 expectedPayout = _expectedPayout(parent, stageId, rewardAmount);
        uint256 balanceBefore = rwaan.balanceOf(wallet);
        uint256 poolBefore = membership.totalPoolPaid();
        uint256 treasuryBefore = membership.totalTreasuryPaid();

        vm.prank(wallet);
        if (stageId == 0) {
            membership.registerWithMaxPayment(sponsor, parent, side, feeAmount, block.timestamp + 10 minutes);
        } else {
            membership.joinStageWithMaxPayment(stageId, parent, side, feeAmount, block.timestamp + 10 minutes);
        }

        assertEq(balanceBefore - rwaan.balanceOf(wallet), feeAmount, "wrong RWAAN wallet debit");
        assertEq(membership.totalPoolPaid() - poolBefore, expectedPayout, "wrong upline payout");
        assertEq(
            membership.totalTreasuryPaid() - treasuryBefore, feeAmount - expectedPayout, "wrong treasury remainder"
        );
        stageFeesCollected[stageId] += feeAmount;
    }

    function _expectMovedPriceRevert(
        address wallet,
        address sponsor,
        address parent,
        BinaryMembershipV1.Side side,
        uint256 stageId
    ) internal {
        oracle.setPrice(3 ether);
        (uint256 staleMaximum,,,) = membership.quoteStagePayment(stageId);
        oracle.setPrice(prices[0]);
        (uint256 requiredNow,,,) = membership.quoteStagePayment(stageId);
        assertGt(requiredNow, staleMaximum, "test quote did not become insufficient");

        uint256 memberCountBefore = membership.memberCount();
        uint256 balanceBefore = rwaan.balanceOf(wallet);
        vm.expectRevert(
            abi.encodeWithSelector(BinaryMembershipV1.PaymentExceedsMaximum.selector, requiredNow, staleMaximum)
        );
        vm.prank(wallet);
        if (stageId == 0) {
            membership.registerWithMaxPayment(sponsor, parent, side, staleMaximum, block.timestamp + 10 minutes);
        } else {
            membership.joinStageWithMaxPayment(stageId, parent, side, staleMaximum, block.timestamp + 10 minutes);
        }

        assertEq(membership.memberCount(), memberCountBefore, "rejected quote changed member count");
        assertEq(rwaan.balanceOf(wallet), balanceBefore, "rejected quote debited RWAAN");
        rejectedMovedPriceQuotes++;
    }

    function _auditMemberState() internal returns (uint256 stageLedger, uint256 memberLedger) {
        uint256 rootAggregate;
        for (uint256 stageId; stageId < STAGE_COUNT; stageId++) {
            BinaryMembershipV1.StageMembership memory rootMem = membership.getStageMembership(ROOT, stageId);
            stageLedger += rootMem.stageEarnings;
            rootAggregate += rootMem.stageEarnings;
            totalRollovers[stageId] += rootMem.rolloverCount;
        }
        assertEq(membership.getMember(ROOT).totalEarned, rootAggregate, "root ledger mismatch");
        memberLedger += rootAggregate;

        for (uint256 i; i < payingCount; i++) {
            uint256 aggregate;
            for (uint256 stageId; stageId < STAGE_COUNT; stageId++) {
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
        uint256 rootBalanceBefore = rwaan.balanceOf(ROOT);
        for (uint256 stageId = 1; stageId < STAGE_COUNT; stageId++) {
            (,,, uint256 milestone, bool eligible) = membership.getAwardInfo(ROOT, stageId);
            assertEq(milestone, 10, "wrong award milestone");
            assertTrue(eligible, "root did not reach award milestone");
            vm.prank(OPERATOR);
            membership.grantPhysicalAward(ROOT, stageId, UNIT);
        }

        assertEq(membership.totalAwardsPaid(), 4 * UNIT, "award accounting");
        assertEq(rwaan.balanceOf(ROOT) - rootBalanceBefore, 4 * UNIT, "root award delta");

        vm.prank(TREASURY);
        membership.withdrawTreasury(UNIT);
        assertEq(rwaan.balanceOf(TREASURY), UNIT / 2, "treasury withdrawal destination");
        assertEq(rwaan.balanceOf(COMPANY), UNIT / 2, "company withdrawal destination");
        assertEq(
            membership.pendingTreasury(),
            membership.totalTreasuryPaid() - 5 * UNIT,
            "pending treasury after awards and withdrawal"
        );
        assertEq(rwaan.balanceOf(address(membership)), membership.pendingTreasury(), "final treasury insolvency");
        assertEq(
            membership.totalPoolPaid() + membership.totalTreasuryPaid(), expectedFees, "post-action fee conservation"
        );
    }

    function _chooseSponsor(uint256 index) internal view returns (address) {
        if (index < 140) return ROOT;
        uint256 sponsorIndex = uint256(keccak256(abi.encodePacked("RWAAN-STRESS-350", index))) % index;
        return wallets[sponsorIndex];
    }

    function _bucket(address member) internal pure returns (uint256) {
        if (member == ROOT) return 0;
        return uint256(uint160(member)) - 0x350000 + 1;
    }

    function _expectedPayout(address parent, uint256 stageId, uint256 rewardAmount)
        internal
        view
        returns (uint256 payout)
    {
        address current = parent;
        for (uint256 level; level < depths[stageId] && current != address(0); level++) {
            payout += rewardAmount;
            BinaryMembershipV1.StageMembership memory mem = membership.getStageMembership(current, stageId);
            address par = mem.parent;
            if (par == address(0)) break;
            BinaryMembershipV1.StageMembership memory parMem = membership.getStageMembership(par, stageId);
            if (parMem.left != current && parMem.right != current) break;
            current = par;
        }
    }

    function _trackQuote(uint256 stageId, uint256 feeAmount) internal {
        if (minQuotedFee[stageId] == 0 || feeAmount < minQuotedFee[stageId]) {
            minQuotedFee[stageId] = feeAmount;
        }
        if (feeAmount > maxQuotedFee[stageId]) maxQuotedFee[stageId] = feeAmount;
    }

    function _report(uint256 expectedFees) internal view {
        console.log("=== V2 / RWAAN FIVE-STAGE CAMPAIGN ===");
        console.log("member wallets             :", campaignWalletCount);
        console.log("paying wallets             :", payingCount);
        console.log("paid placements            :", payingCount * STAGE_COUNT);
        console.log("rejected moved-price quotes:", rejectedMovedPriceQuotes);
        for (uint256 stageId; stageId < STAGE_COUNT; stageId++) {
            console.log("stage", stageId + 1);
            console.log("  RWAAN fees               :", stageFeesCollected[stageId] / UNIT);
            console.log("  RWAAN node rewards       :", stagePoolPaid[stageId] / UNIT);
            console.log("  RWAAN gross treasury     :", stageTreasuryPaid[stageId] / UNIT);
            console.log("  spillover placements     :", spillovers[stageId]);
            console.log("  all member rollovers     :", totalRollovers[stageId]);
            console.log("  spillunder earners       :", spillunderEarners[stageId]);
        }
        console.log("RWAAN fees collected       :", expectedFees / UNIT);
        console.log("RWAAN node rewards         :", membership.totalPoolPaid() / UNIT);
        console.log("RWAAN gross treasury       :", membership.totalTreasuryPaid() / UNIT);
        console.log("RWAAN awards paid          :", membership.totalAwardsPaid() / UNIT);
        console.log("RWAAN treasury withdrawn   :", rwaan.balanceOf(TREASURY) / UNIT);
        console.log("RWAAN company withdrawn    :", rwaan.balanceOf(COMPANY) / UNIT);
        console.log("RWAAN pending treasury     :", membership.pendingTreasury() / UNIT);
        console.log("RWAAN contract balance     :", rwaan.balanceOf(address(membership)) / UNIT);
    }
}
