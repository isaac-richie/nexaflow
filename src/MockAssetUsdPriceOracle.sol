// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IAssetUsdPriceOracle} from "./interfaces/IAssetUsdPriceOracle.sol";

/// @dev Mutable test oracle. Never deploy in production.
contract MockAssetUsdPriceOracle is IAssetUsdPriceOracle {
    uint256 public priceUsd18;
    uint256 public updatedAt;

    constructor(uint256 initialPriceUsd18) {
        setPrice(initialPriceUsd18);
    }

    function setPrice(uint256 newPriceUsd18) public {
        priceUsd18 = newPriceUsd18;
        updatedAt = block.timestamp;
    }

    function setRound(uint256 newPriceUsd18, uint256 newUpdatedAt) external {
        priceUsd18 = newPriceUsd18;
        updatedAt = newUpdatedAt;
    }

    function latestPriceUsd() external view returns (uint256, uint256) {
        return (priceUsd18, updatedAt);
    }
}
