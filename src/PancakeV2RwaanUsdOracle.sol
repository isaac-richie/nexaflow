// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IAssetUsdPriceOracle} from "./interfaces/IAssetUsdPriceOracle.sol";

interface IPancakeV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint256);
}

interface IAggregatorV3 {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/// @title PancakeV2RwaanUsdOracle
/// @notice Permissionlessly maintained RWAAN/USD oracle for BSC mainnet.
/// @dev Combines a PancakeSwap V2 RWAAN/WBNB TWAP with Chainlink BNB/USD.
///      `update()` must be called after each averaging period. The membership
///      contract rejects this oracle when the resulting timestamp is stale.
contract PancakeV2RwaanUsdOracle is IAssetUsdPriceOracle {
    uint256 private constant Q112 = 2 ** 112;
    uint256 private constant ONE = 1e18;

    address public immutable rwaan;
    address public immutable wrappedBnb;
    IPancakeV2Pair public immutable pair;
    IAggregatorV3 public immutable bnbUsdFeed;
    uint256 public immutable period;
    uint256 public immutable bnbFeedMaxAge;
    uint8 public immutable bnbUsdFeedDecimals;

    uint256 public price0CumulativeLast;
    uint32 public blockTimestampLast;
    uint256 public price0AverageX112;
    uint256 public twapUpdatedAt;

    error InvalidConfiguration();
    error InvalidPair();
    error NoLiquidity();
    error PeriodNotElapsed(uint256 elapsed, uint256 required);
    error OracleNotInitialized();
    error InvalidFeedRound();
    error StaleBnbPrice(uint256 updatedAt, uint256 currentTimestamp);

    event OracleUpdated(uint256 price0AverageX112, uint256 updatedAt, uint256 elapsed);

    constructor(
        address _rwaan,
        address _wrappedBnb,
        IPancakeV2Pair _pair,
        IAggregatorV3 _bnbUsdFeed,
        uint256 _period,
        uint256 _bnbFeedMaxAge
    ) {
        if (
            _rwaan == address(0) || _wrappedBnb == address(0) || address(_pair) == address(0)
                || address(_bnbUsdFeed) == address(0) || _period == 0 || _period > type(uint32).max
                || _bnbFeedMaxAge == 0
        ) revert InvalidConfiguration();
        if (_pair.token0() != _rwaan || _pair.token1() != _wrappedBnb) revert InvalidPair();
        if (IERC20Metadata(_rwaan).decimals() != 18 || IERC20Metadata(_wrappedBnb).decimals() != 18) {
            revert InvalidConfiguration();
        }
        uint8 feedDecimals = _bnbUsdFeed.decimals();
        if (feedDecimals > 18) revert InvalidConfiguration();

        rwaan = _rwaan;
        wrappedBnb = _wrappedBnb;
        pair = _pair;
        bnbUsdFeed = _bnbUsdFeed;
        period = _period;
        bnbFeedMaxAge = _bnbFeedMaxAge;
        bnbUsdFeedDecimals = feedDecimals;

        (price0CumulativeLast, blockTimestampLast) = _currentCumulativePrice();
    }

    /// @notice Advance the TWAP. Anyone may call after `period` seconds.
    function update() external returns (uint256 averageX112) {
        (uint256 cumulative, uint32 blockTimestamp) = _currentCumulativePrice();

        uint32 elapsed;
        unchecked {
            elapsed = blockTimestamp - blockTimestampLast;
        }
        if (elapsed < period) revert PeriodNotElapsed(elapsed, period);

        uint256 cumulativeDelta;
        unchecked {
            cumulativeDelta = cumulative - price0CumulativeLast;
        }
        averageX112 = cumulativeDelta / elapsed;
        if (averageX112 == 0) revert NoLiquidity();

        price0AverageX112 = averageX112;
        price0CumulativeLast = cumulative;
        blockTimestampLast = blockTimestamp;
        twapUpdatedAt = block.timestamp;

        emit OracleUpdated(averageX112, block.timestamp, elapsed);
    }

    function latestPriceUsd() external view returns (uint256 priceUsd18, uint256 updatedAt) {
        uint256 averageX112 = price0AverageX112;
        if (averageX112 == 0 || twapUpdatedAt == 0) revert OracleNotInitialized();

        (uint80 roundId, int256 answer,, uint256 feedUpdatedAt, uint80 answeredInRound) =
            bnbUsdFeed.latestRoundData();
        if (
            roundId == 0 || answer <= 0 || feedUpdatedAt == 0 || feedUpdatedAt > block.timestamp
                || answeredInRound < roundId
        ) revert InvalidFeedRound();
        if (block.timestamp - feedUpdatedAt > bnbFeedMaxAge) {
            revert StaleBnbPrice(feedUpdatedAt, block.timestamp);
        }

        uint8 feedDecimals = bnbUsdFeedDecimals;
        uint256 bnbUsd18 = uint256(answer);
        if (feedDecimals < 18) {
            bnbUsd18 *= 10 ** uint256(18 - feedDecimals);
        }

        // price0 is WBNB base units per RWAAN base unit. Both tokens have 18
        // decimals, so this first resolves WBNB wei per whole RWAAN and then
        // converts that WBNB value into 18-decimal USD.
        uint256 wbnbPerRwaan = Math.mulDiv(averageX112, ONE, Q112);
        priceUsd18 = Math.mulDiv(wbnbPerRwaan, bnbUsd18, ONE);
        if (priceUsd18 == 0) revert InvalidFeedRound();

        updatedAt = twapUpdatedAt < feedUpdatedAt ? twapUpdatedAt : feedUpdatedAt;
    }

    /// @dev Counterfactual cumulative price, matching the Pancake/Uniswap V2
    ///      pair update formula without requiring a swap or sync transaction.
    function _currentCumulativePrice() internal view returns (uint256 cumulative, uint32 blockTimestamp) {
        cumulative = pair.price0CumulativeLast();
        (uint112 reserve0, uint112 reserve1, uint32 pairTimestamp) = pair.getReserves();
        if (reserve0 == 0 || reserve1 == 0) revert NoLiquidity();

        blockTimestamp = uint32(block.timestamp);
        if (pairTimestamp != blockTimestamp) {
            uint32 elapsed;
            unchecked {
                elapsed = blockTimestamp - pairTimestamp;
                cumulative += ((uint256(reserve1) << 112) / reserve0) * elapsed;
            }
        }
    }
}
