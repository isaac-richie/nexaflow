// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Test-only USDC-shaped token for public testnet campaigns.
/// @dev Uses six decimals and owner-gated minting. It must never be presented
///      as real USDC or used outside disposable test environments.
contract MockUSDC6 is ERC20, Ownable {
    constructor(address initialOwner) ERC20("Mock USDC", "mUSDC") Ownable(initialOwner) {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function batchMint(address[] calldata recipients, uint256[] calldata amounts) external onlyOwner {
        uint256 length = recipients.length;
        require(length == amounts.length, "length mismatch");

        for (uint256 i; i < length; i++) {
            if (amounts[i] != 0) _mint(recipients[i], amounts[i]);
        }
    }
}
