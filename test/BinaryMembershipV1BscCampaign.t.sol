// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {MockUSDC6} from "../src/MockUSDC6.sol";
import {MockUSDT18} from "../src/MockUSDT18.sol";
import {DeployBscTestnet} from "../script/DeployBscTestnet.s.sol";

contract DeployBscTestnetHarness is DeployBscTestnet {
    function configureAndVerify(IERC20Metadata paymentToken, BinaryMembershipV1 target) external {
        _configureAndVerify(paymentToken, target);
    }
}

contract BinaryMembershipV1BscCampaignTest is Test {
    uint256 internal constant UNIT = 1e18;
    uint256 internal constant WALLET_COUNT = 140;
    address internal constant ROOT = address(0xBEEF);
    address internal constant OPERATOR = address(0xA11CE);
    address internal constant TREASURY = address(0x7EA5);

    MockUSDT18 internal token;
    BinaryMembershipV1 internal membership;
    address[] internal wallets;
    uint256[6] internal fees = [uint256(20 * UNIT), 60 * UNIT, 180 * UNIT, 540 * UNIT, 1_620 * UNIT, 4_860 * UNIT];

    function setUp() public {
        token = new MockUSDT18(address(this));
        membership = new BinaryMembershipV1(IERC20(address(token)), TREASURY, address(this), 0, ROOT);
        membership.grantRole(membership.OPERATOR_ROLE(), OPERATOR);
        membership.configureStages(
            fees,
            [uint256(5 * UNIT), 10 * UNIT, 25 * UNIT, 80 * UNIT, 250 * UNIT, 800 * UNIT],
            [uint256(6), 14, 14, 14, 14, 14],
            [uint256(2), 3, 3, 3, 3, 3],
            [uint256(0), 10, 10, 10, 10, 8]
        );
        membership.setCycleGuardEnabled(true);

        vm.prank(ROOT);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);
        for (uint256 stageId = 1; stageId < 6; stageId++) {
            vm.prank(OPERATOR);
            membership.enrollStageRoot(ROOT, stageId);
        }

        for (uint256 i; i < WALLET_COUNT; i++) {
            // Safe because i is bounded by WALLET_COUNT (140).
            // forge-lint: disable-next-line(unsafe-typecast)
            address member = address(uint160(10_000 + i));
            wallets.push(member);
            token.mint(member, 10_000 * UNIT);
            vm.prank(member);
            token.approve(address(membership), type(uint256).max);
        }
    }

    function test_BscCampaign_100WalletCheckpoint_Then140AwardExtension() public {
        for (uint256 i; i < WALLET_COUNT; i++) {
            address sponsor = i < 10 ? ROOT : wallets[(i - 10) / 2];
            (address parent, BinaryMembershipV1.Side side) = membership.findPlacementSlot(sponsor, 0);
            vm.prank(wallets[i]);
            membership.register(sponsor, parent, side);
        }

        for (uint256 stageId = 1; stageId < 6; stageId++) {
            for (uint256 i; i < WALLET_COUNT; i++) {
                (address parent, BinaryMembershipV1.Side side) = membership.findOpenSlot(ROOT, stageId);
                vm.prank(wallets[i]);
                membership.joinStage(stageId, parent, side);

                if (i == 99) {
                    BinaryMembershipV1.StageMembership memory checkpoint = membership.getStageMembership(ROOT, stageId);
                    assertEq(checkpoint.rolloverCount, 7, "100-wallet rollover checkpoint");
                    assertEq(checkpoint.slotsFilledBelow, 2, "100-wallet slot checkpoint");
                    (,,,, bool eligibleAt100) = membership.getAwardInfo(ROOT, stageId);
                    assertFalse(eligibleAt100, "award unlocked with only 100 wallets");
                }

                if (i == 111 && stageId == 4) {
                    (,,,, bool stage4EligibleAtEight) = membership.getAwardInfo(ROOT, stageId);
                    assertFalse(stage4EligibleAtEight, "$1,620 unlocked at eight rollovers");
                }

                if (i == 111 && stageId == 5) {
                    (,,, uint256 nextMilestone, bool stage5EligibleAtEight) = membership.getAwardInfo(ROOT, stageId);
                    assertEq(nextMilestone, 8, "wrong final-stage milestone");
                    assertTrue(stage5EligibleAtEight, "$4,860 did not unlock at eight rollovers");
                    vm.prank(OPERATOR);
                    membership.grantPhysicalAward(ROOT, stageId, UNIT);
                }
            }

            BinaryMembershipV1.StageMembership memory completed = membership.getStageMembership(ROOT, stageId);
            assertEq(completed.rolloverCount, 10, "140-wallet rollover checkpoint");
            assertEq(completed.slotsFilledBelow, 0, "140-wallet board should be exact");

            if (stageId < 5) {
                (,,, uint256 nextMilestone, bool eligible) = membership.getAwardInfo(ROOT, stageId);
                assertEq(nextMilestone, 10, "wrong ten-rollover milestone");
                assertTrue(eligible, "ten-rollover award not unlocked");
                vm.prank(OPERATOR);
                membership.grantPhysicalAward(ROOT, stageId, UNIT);
            } else {
                (,,, uint256 nextMilestone, bool eligible) = membership.getAwardInfo(ROOT, stageId);
                assertEq(nextMilestone, 16, "final-stage repeat milestone");
                assertFalse(eligible, "second final-stage award unlocked early");
            }
        }

        vm.expectRevert(abi.encodeWithSelector(BinaryMembershipV1.InvalidStage.selector, 0));
        vm.prank(OPERATOR);
        membership.grantPhysicalAward(ROOT, 0, UNIT);

        uint256 expectedFees;
        for (uint256 stageId; stageId < 6; stageId++) {
            expectedFees += WALLET_COUNT * fees[stageId];
        }

        uint256 stageLedger;
        for (uint256 stageId; stageId < 6; stageId++) {
            stageLedger += membership.getStageMembership(ROOT, stageId).stageEarnings;
        }
        uint256 memberLedger;
        for (uint256 i; i < WALLET_COUNT; i++) {
            uint256 walletLedger;
            for (uint256 stageId; stageId < 6; stageId++) {
                BinaryMembershipV1.StageMembership memory stage = membership.getStageMembership(wallets[i], stageId);
                assertTrue(stage.enrolled, "wallet missing stage");
                walletLedger += stage.stageEarnings;
                stageLedger += stage.stageEarnings;
            }
            assertEq(membership.getMember(wallets[i]).totalEarned, walletLedger, "wallet ledger mismatch");
            memberLedger += walletLedger;
        }

        assertEq(membership.memberCount(), WALLET_COUNT + 1, "member count");
        assertEq(stageLedger, membership.totalPoolPaid(), "stage earnings != pool");
        assertEq(
            memberLedger + membership.getMember(ROOT).totalEarned, membership.totalPoolPaid(), "member sum != pool"
        );
        assertEq(membership.totalPoolPaid() + membership.totalTreasuryPaid(), expectedFees, "fee conservation");
        assertEq(token.balanceOf(address(membership)), membership.pendingTreasury(), "treasury insolvency");
        assertEq(membership.totalAwardsPaid(), 5 * UNIT, "award total");
    }

    function test_DeploymentDerivesUnitAndStoresExactBep20UsdtFees() public {
        DeployBscTestnetHarness harness = new DeployBscTestnetHarness();
        MockUSDT18 paymentToken = new MockUSDT18(address(this));
        BinaryMembershipV1 target =
            new BinaryMembershipV1(IERC20(address(paymentToken)), TREASURY, address(harness), 0, ROOT);

        harness.configureAndVerify(IERC20Metadata(address(paymentToken)), target);

        assertEq(target.getStageConfig(0).fee, 20e18, "$20 stage scaled incorrectly");
        assertEq(target.getStageConfig(5).fee, 4_860e18, "$4,860 stage scaled incorrectly");
        assertEq(target.getStageConfig(5).nodeReward, 800e18, "final reward scaled incorrectly");
    }

    function test_DeploymentRejectsSixDecimalPaymentToken() public {
        DeployBscTestnetHarness harness = new DeployBscTestnetHarness();
        MockUSDC6 paymentToken = new MockUSDC6(address(this));
        BinaryMembershipV1 target =
            new BinaryMembershipV1(IERC20(address(paymentToken)), TREASURY, address(harness), 0, ROOT);

        vm.expectRevert(bytes("payment token must have 18 decimals"));
        harness.configureAndVerify(IERC20Metadata(address(paymentToken)), target);
    }
}
