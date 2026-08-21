// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";

import {
    PancakeV2RwaanUsdOracle,
    IPancakeV2Pair,
    IAggregatorV3
} from "../src/PancakeV2RwaanUsdOracle.sol";
import {MockERC20} from "../src/MockERC20.sol";

contract MockPancakePair is IPancakeV2Pair {
    address public immutable token0;
    address public immutable token1;
    uint112 public reserve0;
    uint112 public reserve1;
    uint32 public reserveTimestamp;
    uint256 public cumulative;

    constructor(address _token0, address _token1, uint112 _reserve0, uint112 _reserve1) {
        token0 = _token0;
        token1 = _token1;
        reserve0 = _reserve0;
        reserve1 = _reserve1;
        reserveTimestamp = uint32(block.timestamp);
    }

    function setReserves(uint112 _reserve0, uint112 _reserve1, uint32 _timestamp) external {
        reserve0 = _reserve0;
        reserve1 = _reserve1;
        reserveTimestamp = _timestamp;
    }

    function setCumulative(uint256 value) external {
        cumulative = value;
    }

    function getReserves() external view returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, reserveTimestamp);
    }

    function price0CumulativeLast() external view returns (uint256) {
        return cumulative;
    }
}

contract MockAggregator is IAggregatorV3 {
    uint8 public immutable decimals;
    int256 public answer;
    uint256 public updatedAt;
    uint80 public roundId = 1;
    uint80 public answeredInRound = 1;

    constructor(uint8 _decimals, int256 _answer) {
        decimals = _decimals;
        answer = _answer;
        updatedAt = block.timestamp;
    }

    function setRound(int256 _answer, uint256 _updatedAt) external {
        answer = _answer;
        updatedAt = _updatedAt;
    }

    function setRoundMetadata(uint80 _roundId, uint80 _answeredInRound) external {
        roundId = _roundId;
        answeredInRound = _answeredInRound;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (roundId, answer, updatedAt, updatedAt, answeredInRound);
    }
}

contract PancakeV2RwaanUsdOracleTest is Test {
    uint256 internal constant PERIOD = 30 minutes;
    uint256 internal constant FEED_MAX_AGE = 2 hours;

    MockERC20 internal rwaan;
    MockERC20 internal wbnb;
    MockPancakePair internal pair;
    MockAggregator internal feed;
    PancakeV2RwaanUsdOracle internal oracle;

    function setUp() public {
        vm.warp(10 days);
        rwaan = new MockERC20("Rawli Analytics", "RWAAN", 18);
        wbnb = new MockERC20("Wrapped BNB", "WBNB", 18);

        // 1,000,000 RWAAN : 0.1 WBNB => 0.0000001 WBNB per RWAAN.
        pair = new MockPancakePair(address(rwaan), address(wbnb), uint112(1_000_000 ether), uint112(0.1 ether));
        feed = new MockAggregator(8, 600e8); // BNB = $600
        oracle = new PancakeV2RwaanUsdOracle(
            address(rwaan), address(wbnb), pair, feed, PERIOD, FEED_MAX_AGE
        );
    }

    function test_TwapAndChainlinkComposeIntoUsdPrice() public {
        vm.warp(block.timestamp + PERIOD);
        feed.setRound(600e8, block.timestamp);
        oracle.update();

        (uint256 priceUsd18, uint256 updatedAt) = oracle.latestPriceUsd();
        // Two intentional floor operations (Q112 -> WBNB -> USD) can lose a
        // few hundred wei at this very small token price.
        assertApproxEqAbs(priceUsd18, 0.00006 ether, 1_000);
        assertEq(updatedAt, block.timestamp);
    }

    function test_RevertBeforeFirstTwapUpdate() public {
        vm.expectRevert(PancakeV2RwaanUsdOracle.OracleNotInitialized.selector);
        oracle.latestPriceUsd();
    }

    function test_RevertWhenPeriodHasNotElapsed() public {
        vm.warp(block.timestamp + PERIOD - 1);
        vm.expectRevert(
            abi.encodeWithSelector(PancakeV2RwaanUsdOracle.PeriodNotElapsed.selector, PERIOD - 1, PERIOD)
        );
        oracle.update();
    }

    function test_RevertWhenBnbFeedIsStale() public {
        vm.warp(block.timestamp + PERIOD);
        feed.setRound(600e8, block.timestamp);
        oracle.update();

        uint256 feedUpdatedAt = block.timestamp;
        vm.warp(block.timestamp + FEED_MAX_AGE + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                PancakeV2RwaanUsdOracle.StaleBnbPrice.selector, feedUpdatedAt, block.timestamp
            )
        );
        oracle.latestPriceUsd();
    }

    function test_RevertForWrongPairOrder() public {
        MockPancakePair reversed = new MockPancakePair(
            address(wbnb), address(rwaan), uint112(0.1 ether), uint112(1_000_000 ether)
        );

        vm.expectRevert(PancakeV2RwaanUsdOracle.InvalidPair.selector);
        new PancakeV2RwaanUsdOracle(address(rwaan), address(wbnb), reversed, feed, PERIOD, FEED_MAX_AGE);
    }

    function test_RevertForIncompleteChainlinkRound() public {
        vm.warp(block.timestamp + PERIOD);
        feed.setRound(600e8, block.timestamp);
        feed.setRoundMetadata(2, 1);
        oracle.update();

        vm.expectRevert(PancakeV2RwaanUsdOracle.InvalidFeedRound.selector);
        oracle.latestPriceUsd();
    }

    function test_RevertForPeriodOutsideUint32Clock() public {
        vm.expectRevert(PancakeV2RwaanUsdOracle.InvalidConfiguration.selector);
        new PancakeV2RwaanUsdOracle(
            address(rwaan), address(wbnb), pair, feed, uint256(type(uint32).max) + 1, FEED_MAX_AGE
        );
    }

    function test_SameBlockReserveManipulationCannotChangePublishedPrice() public {
        vm.warp(block.timestamp + PERIOD);
        feed.setRound(600e8, block.timestamp);
        oracle.update();
        (uint256 originalPrice,) = oracle.latestPriceUsd();

        // Model a pair sync into a 4x manipulated spot price. The oracle's
        // published TWAP is immutable until a complete new period elapses.
        pair.setCumulative(oracle.price0CumulativeLast());
        pair.setReserves(uint112(500_000 ether), uint112(0.2 ether), uint32(block.timestamp));

        (uint256 unchangedPrice,) = oracle.latestPriceUsd();
        assertEq(unchangedPrice, originalPrice);

        vm.warp(block.timestamp + PERIOD - 1);
        feed.setRound(600e8, block.timestamp);
        vm.expectRevert(
            abi.encodeWithSelector(PancakeV2RwaanUsdOracle.PeriodNotElapsed.selector, PERIOD - 1, PERIOD)
        );
        oracle.update();
        (unchangedPrice,) = oracle.latestPriceUsd();
        assertEq(unchangedPrice, originalPrice);

        vm.warp(block.timestamp + 1);
        feed.setRound(600e8, block.timestamp);
        oracle.update();
        (uint256 manipulatedTwap,) = oracle.latestPriceUsd();
        assertApproxEqAbs(manipulatedTwap, originalPrice * 4, 4_000);
    }
}
