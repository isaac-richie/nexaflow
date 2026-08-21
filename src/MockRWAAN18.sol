// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Test-only 18-decimal RWAAN stand-in for BSC testnet campaigns.
contract MockRWAAN18 is ERC20, Ownable {
    constructor(address initialOwner) ERC20("Mock Rawli Analytics", "mRWAAN") Ownable(initialOwner) {}

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function batchMint(address[] calldata recipients, uint256[] calldata amounts) external onlyOwner {
        require(recipients.length == amounts.length, "length mismatch");
        for (uint256 i; i < recipients.length; i++) {
            if (amounts[i] != 0) _mint(recipients[i], amounts[i]);
        }
    }
}
