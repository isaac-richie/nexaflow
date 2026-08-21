// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {BinaryMembershipV2} from "../src/BinaryMembershipV2.sol";
import {PancakeV2RwaanUsdOracle, IPancakeV2Pair, IAggregatorV3} from "../src/PancakeV2RwaanUsdOracle.sol";

/// @notice Run with `--fork-url $BSC_MAINNET_RPC_URL`.
contract BinaryMembershipV2BscForkTest is Test {
    address internal constant RWAAN = 0xACB921bf2Dac2F7E8E101AAd9CA013d6Af5C648a;
    address internal constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address internal constant PAIR = 0xA285059BBc89Fe9B43414D098318675462aaa3e6;
    address internal constant BNB_USD_FEED = 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE;

    function test_Fork_LiveRwaanOracleAndRegistrationTransfer() public {
        if (block.chainid != 56) return;

        IERC20Metadata token = IERC20Metadata(RWAAN);
        assertEq(token.name(), "Rawli Analytics");
        assertEq(token.symbol(), "RWAAN");
        assertEq(token.decimals(), 18);
        assertEq(IPancakeV2Pair(PAIR).token0(), RWAAN);
        assertEq(IPancakeV2Pair(PAIR).token1(), WBNB);

        PancakeV2RwaanUsdOracle oracle = new PancakeV2RwaanUsdOracle(
            RWAAN, WBNB, IPancakeV2Pair(PAIR), IAggregatorV3(BNB_USD_FEED), 2 hours, 3 hours
        );
        vm.warp(block.timestamp + 2 hours);
        oracle.update();
        (uint256 priceUsd18,) = oracle.latestPriceUsd();
        assertGt(priceUsd18, 0);

        address admin = address(this);
        address treasury = address(0x7000);
        address company = address(0x8000);
        address root = address(0x1000);
        address member = address(0x2000);
        BinaryMembershipV2 membership =
            new BinaryMembershipV2(token, oracle, 3 hours, treasury, company, admin, 0, root);
        membership.configureStages(
            [uint256(20 ether), 60 ether, 180 ether, 540 ether, 1_620 ether, 4_860 ether],
            [uint256(5 ether), 10 ether, 25 ether, 80 ether, 250 ether, 800 ether],
            [uint256(6), 14, 14, 14, 14, 14],
            [uint256(2), 3, 3, 3, 3, 3],
            [uint256(0), 10, 10, 10, 10, 8]
        );

        vm.prank(root);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);

        // Acquire tokens through the live token's buy path, then exercise the
        // wallet -> membership -> upline path used by a real registration.
        vm.prank(PAIR);
        IERC20(RWAAN).transfer(member, 1_000_000 ether);
        uint256 acquired = IERC20(RWAAN).balanceOf(member);
        (uint256 fee, uint256 reward,,) = membership.quoteStagePayment(0);
        assertGe(acquired, fee);

        vm.prank(member);
        IERC20(RWAAN).approve(address(membership), fee);
        uint256 rootBefore = IERC20(RWAAN).balanceOf(root);
        uint256 memberBefore = IERC20(RWAAN).balanceOf(member);

        vm.prank(member);
        membership.registerWithMaxPayment(root, root, BinaryMembershipV1.Side.Left, fee, block.timestamp + 1 hours);

        assertEq(memberBefore - IERC20(RWAAN).balanceOf(member), fee, "registration transfer taxed");
        assertEq(IERC20(RWAAN).balanceOf(root) - rootBefore, reward, "upline transfer taxed");
        assertEq(membership.pendingTreasury(), fee - reward);
    }
}
