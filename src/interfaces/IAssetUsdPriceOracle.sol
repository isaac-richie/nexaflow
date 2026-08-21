// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @notice USD price of one whole payment token, scaled to 18 decimals.
interface IAssetUsdPriceOracle {
    function latestPriceUsd() external view returns (uint256 priceUsd18, uint256 updatedAt);
}
