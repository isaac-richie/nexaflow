// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {BinaryMembershipV2} from "../src/BinaryMembershipV2.sol";
import {MockAssetUsdPriceOracle} from "../src/MockAssetUsdPriceOracle.sol";
import {MockERC20} from "../src/MockERC20.sol";

/// @notice Dynamic-price end-to-end pressure test: 2,000 paying wallets enter
///         all six stages while the RWAAN/USD price changes on every entry.
contract BinaryMembershipV2Stress2000Test is Test {
    uint256 internal constant WALLET_COUNT = 2_000;
    address internal constant ADMIN = address(0xA11CE);
    address internal constant TREASURY = address(0x7000);
    address internal constant COMPANY = address(0x8000);
    address internal constant ROOT = address(0x1000);
    address internal constant OPERATOR = address(0xBEEF);

    MockERC20 internal rwaan;
    MockAssetUsdPriceOracle internal oracle;
    BinaryMembershipV2 internal membership;

    uint256[6] internal prices =
        [uint256(0.00005 ether), 0.0000725 ether, 0.0001 ether, 0.0002 ether, 0.01 ether, 3 ether];

    function setUp() public {
        vm.warp(30 days);
        rwaan = new MockERC20("Rawli Analytics", "RWAAN", 18);
        oracle = new MockAssetUsdPriceOracle(prices[0]);
        membership =
            new BinaryMembershipV2(IERC20Metadata(address(rwaan)), oracle, 2 hours, TREASURY, COMPANY, ADMIN, 0, ROOT);

        vm.startPrank(ADMIN);
        membership.configureStages(
            [uint256(20 ether), 60 ether, 180 ether, 540 ether, 1_620 ether, 4_860 ether],
            [uint256(5 ether), 10 ether, 25 ether, 80 ether, 250 ether, 800 ether],
            [uint256(6), 14, 14, 14, 14, 14],
            [uint256(2), 3, 3, 3, 3, 3],
            [uint256(0), 10, 10, 10, 10, 8]
        );
        membership.grantRole(membership.OPERATOR_ROLE(), OPERATOR);
        membership.setCycleGuardEnabled(true);
        vm.stopPrank();

        vm.prank(ROOT);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);
        for (uint256 stageId = 1; stageId < 6; stageId++) {
            vm.prank(OPERATOR);
            membership.enrollStageRoot(ROOT, stageId);
        }

        for (uint256 i; i < WALLET_COUNT; i++) {
            address member = _user(i);
            rwaan.mint(member, 200_000_000 ether);
            vm.prank(member);
            rwaan.approve(address(membership), type(uint256).max);
        }
    }

    function test_2000Wallets_AllStages_VariablePrices_SpilloverSpillunderAndRollover() public {
        // This is a state-space pressure test, not a single-transaction gas
        // benchmark. Without metering, Foundry's synthetic test transaction
        // would hit its 2^30 gas ceiling halfway through the 12,000 entries.
        vm.pauseGasMetering();
        uint256 totalFees;

        for (uint256 stageId; stageId < 6; stageId++) {
            for (uint256 i; i < WALLET_COUNT; i++) {
                oracle.setPrice(prices[(i + stageId) % prices.length]);
                (uint256 maximumPayment,,,) = membership.quoteStagePayment(stageId);
                totalFees += maximumPayment;

                address sponsor = i == 0 ? ROOT : _user((i - 1) / 2);
                (address parent, BinaryMembershipV1.Side side) = stageId % 2 == 0
                    ? membership.findPlacementSlot(sponsor, stageId)
                    : membership.findOpenSlot(ROOT, stageId);

                uint256 beforeBalance = rwaan.balanceOf(_user(i));
                vm.prank(_user(i));
                if (stageId == 0) {
                    membership.registerWithMaxPayment(sponsor, parent, side, maximumPayment, block.timestamp + 1 hours);
                } else {
                    membership.joinStageWithMaxPayment(stageId, parent, side, maximumPayment, block.timestamp + 1 hours);
                }
                assertEq(beforeBalance - rwaan.balanceOf(_user(i)), maximumPayment, "wrong wallet debit");
            }
        }

        assertEq(membership.memberCount(), WALLET_COUNT + 1, "member count");
        assertEq(membership.totalPoolPaid() + membership.totalTreasuryPaid(), totalFees, "fee conservation");
        assertEq(membership.totalTreasuryPaid(), membership.pendingTreasury(), "treasury accounting");
        assertEq(rwaan.balanceOf(address(membership)), membership.pendingTreasury(), "contract solvency");
        assertGt(membership.totalPoolPaid(), 0, "no node rewards");
        assertGt(membership.pendingTreasury(), 0, "no treasury fees");

        for (uint256 stageId; stageId < 6; stageId++) {
            uint256 rollovers;
            for (uint256 i; i < WALLET_COUNT; i++) {
                rollovers += membership.getStageMembership(_user(i), stageId).rolloverCount;
            }
            rollovers += membership.getStageMembership(ROOT, stageId).rolloverCount;
            assertGt(rollovers, 0, "stage had no rollover");
        }
        vm.resumeGasMetering();
    }

    function _user(uint256 index) internal pure returns (address) {
        return address(uint160(0xD00000 + index));
    }
}
