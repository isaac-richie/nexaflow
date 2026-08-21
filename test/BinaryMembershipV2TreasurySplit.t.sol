// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {BinaryMembershipV2} from "../src/BinaryMembershipV2.sol";
import {MockAssetUsdPriceOracle} from "../src/MockAssetUsdPriceOracle.sol";
import {MockRWAAN18} from "../src/MockRWAAN18.sol";

contract BinaryMembershipV2TreasurySplitTest is Test {
    event TreasuryWithdrawn(address indexed to, uint256 amount);
    event CompanyProfitWithdrawn(address indexed companyWallet, uint256 amount);
    event TreasuryWithdrawalSplit(uint256 totalAmount, uint256 treasuryAmount, uint256 companyAmount);

    address internal constant TREASURY = address(0x7000);
    address internal constant COMPANY = address(0x8000);
    address internal constant ROOT = address(0x1000);
    address internal constant OUTSIDER = address(0xBAD);

    MockRWAAN18 internal rwaan;
    MockAssetUsdPriceOracle internal oracle;
    BinaryMembershipV2 internal membership;

    function setUp() public {
        vm.warp(30 days);
        rwaan = new MockRWAAN18(address(this));
        oracle = new MockAssetUsdPriceOracle(0.0001 ether);
        membership = new BinaryMembershipV2(
            IERC20Metadata(address(rwaan)), oracle, 2 hours, TREASURY, COMPANY, address(this), 0, ROOT
        );
        membership.grantRole(membership.TREASURY_ROLE(), TREASURY);

        rwaan.mint(address(this), 101 ether);
        rwaan.approve(address(membership), type(uint256).max);
        membership.fundTreasury(101 ether);
    }

    function test_WithdrawalSplitsExactlyFiftyFifty() public {
        vm.expectEmit(true, false, false, true, address(membership));
        emit TreasuryWithdrawn(TREASURY, 20 ether);
        vm.expectEmit(true, false, false, true, address(membership));
        emit CompanyProfitWithdrawn(COMPANY, 20 ether);
        vm.expectEmit(false, false, false, true, address(membership));
        emit TreasuryWithdrawalSplit(40 ether, 20 ether, 20 ether);

        vm.prank(TREASURY);
        membership.withdrawTreasury(40 ether);

        assertEq(rwaan.balanceOf(TREASURY), 20 ether, "treasury did not receive 50%");
        assertEq(rwaan.balanceOf(COMPANY), 20 ether, "company did not receive 50%");
        assertEq(membership.pendingTreasury(), 61 ether, "pending liability mismatch");
        assertEq(rwaan.balanceOf(address(membership)), 61 ether, "contract balance mismatch");
        assertEq(membership.totalTreasuryPaid(), 101 ether, "gross accounting changed on withdrawal");
    }

    function test_OddBaseUnitRemainderGoesToTreasury() public {
        vm.prank(TREASURY);
        membership.withdrawTreasury(3);

        assertEq(rwaan.balanceOf(TREASURY), 2, "treasury should receive remainder");
        assertEq(rwaan.balanceOf(COMPANY), 1, "company exceeded half");
        assertEq(membership.pendingTreasury(), 101 ether - 3, "pending liability mismatch");
        assertEq(rwaan.balanceOf(address(membership)), membership.pendingTreasury(), "insolvent after odd split");
    }

    function test_OnlyTreasuryRoleCanTriggerSplit() public {
        vm.prank(OUTSIDER);
        vm.expectRevert();
        membership.withdrawTreasury(10 ether);

        assertEq(rwaan.balanceOf(TREASURY), 0, "unauthorized treasury payment");
        assertEq(rwaan.balanceOf(COMPANY), 0, "unauthorized company payment");
        assertEq(membership.pendingTreasury(), 101 ether, "unauthorized liability change");
    }

    function test_PauseBlocksBothPayoutDestinations() public {
        membership.grantRole(membership.PAUSER_ROLE(), address(this));
        membership.pause();

        vm.prank(TREASURY);
        vm.expectRevert();
        membership.withdrawTreasury(10 ether);

        assertEq(rwaan.balanceOf(TREASURY), 0);
        assertEq(rwaan.balanceOf(COMPANY), 0);
    }

    function test_AdminCanRotateDistinctPayoutWallets() public {
        address newCompany = address(0x8001);
        address newTreasury = address(0x7001);

        membership.setCompanyWallet(newCompany);
        membership.setTreasury(newTreasury);

        assertEq(membership.companyWallet(), newCompany);
        assertEq(membership.treasury(), newTreasury);
    }

    function test_PayoutWalletsCanNeverCollide() public {
        vm.expectRevert(abi.encodeWithSelector(BinaryMembershipV2.PayoutWalletCollision.selector, TREASURY));
        membership.setCompanyWallet(TREASURY);

        vm.expectRevert(abi.encodeWithSelector(BinaryMembershipV2.PayoutWalletCollision.selector, COMPANY));
        membership.setTreasury(COMPANY);
    }

    function test_ConstructorRejectsZeroOrCollidingCompanyWallet() public {
        vm.expectRevert(BinaryMembershipV1.ZeroAddress.selector);
        new BinaryMembershipV2(
            IERC20Metadata(address(rwaan)), oracle, 2 hours, TREASURY, address(0), address(this), 0, ROOT
        );

        vm.expectRevert(abi.encodeWithSelector(BinaryMembershipV2.PayoutWalletCollision.selector, TREASURY));
        new BinaryMembershipV2(
            IERC20Metadata(address(rwaan)), oracle, 2 hours, TREASURY, TREASURY, address(this), 0, ROOT
        );
    }

    function test_RevertWhenSplitExceedsPendingTreasury() public {
        vm.prank(TREASURY);
        vm.expectRevert(
            abi.encodeWithSelector(BinaryMembershipV1.InsufficientPendingTreasury.selector, 101 ether, 102 ether)
        );
        membership.withdrawTreasury(102 ether);

        assertEq(rwaan.balanceOf(address(membership)), 101 ether);
        assertEq(membership.pendingTreasury(), 101 ether);
    }
}
