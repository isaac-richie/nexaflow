// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";

import {MockRWAAN18} from "../src/MockRWAAN18.sol";
import {BscTestnetActors} from "./BscTestnetActors.sol";

contract ProvisionBscWallets is BscTestnetActors {
    function run() external {
        _requireSupportedChain();

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        string memory mnemonic = vm.envString("TESTNET_MNEMONIC");
        MockRWAAN18 token = MockRWAAN18(vm.envAddress("MOCK_RWAAN_ADDRESS"));
        uint32 start = uint32(vm.envOr("WALLET_START", uint256(0)));
        uint32 end = uint32(vm.envOr("WALLET_END", uint256(100)));
        uint256 tokenTarget = vm.envOr("MEMBER_MRWAAN", uint256(10_000e18));
        uint256 gasTarget = vm.envOr("MEMBER_GAS_WEI", uint256(1e15));
        require(start < end && end <= 500, "invalid wallet range");

        uint256 length = end - start;
        address[] memory recipients = new address[](length);
        uint256[] memory mintAmounts = new uint256[](length);

        for (uint32 index = start; index < end; index++) {
            uint256 offset = index - start;
            address member = _memberAddress(mnemonic, index);
            recipients[offset] = member;
            uint256 balance = token.balanceOf(member);
            if (balance < tokenTarget) mintAmounts[offset] = tokenTarget - balance;
        }

        vm.startBroadcast(deployerKey);
        token.batchMint(recipients, mintAmounts);
        for (uint256 i; i < length; i++) {
            address recipient = recipients[i];
            if (recipient.balance >= gasTarget) continue;
            (bool sent,) = payable(recipient).call{value: gasTarget - recipient.balance}("");
            require(sent, "member gas funding failed");
        }
        vm.stopBroadcast();

        console2.log("provisioned wallet start", start);
        console2.log("provisioned wallet end  ", end);
        console2.log("target mRWAAN per wallet", tokenTarget);
        console2.log("target wei per wallet   ", gasTarget);
    }
}
