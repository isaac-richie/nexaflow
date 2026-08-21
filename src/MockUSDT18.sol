// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Test-only token matching the 18-decimal shape of BEP-20 USDT on BSC.
/// @dev This is not real USDT. It must only be used in disposable test environments.
contract MockUSDT18 is ERC20, Ownable {
    constructor(address initialOwner) ERC20("Mock USDT", "mUSDT") Ownable(initialOwner) {}

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
