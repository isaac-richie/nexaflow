// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";

abstract contract BscTestnetActors is Script {
    uint32 internal constant ROOT_INDEX = 1_000;
    uint32 internal constant OPERATOR_INDEX = 1_001;
    uint32 internal constant TREASURY_INDEX = 1_002;
    uint32 internal constant PAUSER_INDEX = 1_003;
    uint32 internal constant COMPANY_INDEX = 1_004;
    uint256 internal constant BSC_TESTNET_CHAIN_ID = 97;

    function _requireSupportedChain() internal view {
        bool localAllowed = vm.envOr("ALLOW_LOCAL", false);
        require(block.chainid == BSC_TESTNET_CHAIN_ID || localAllowed, "wrong chain");
    }

    function _memberKey(string memory mnemonic, uint32 index) internal pure returns (uint256) {
        return vm.deriveKey(mnemonic, index);
    }

    function _memberAddress(string memory mnemonic, uint32 index) internal pure returns (address) {
        return vm.addr(_memberKey(mnemonic, index));
    }

    function _sponsorFor(string memory mnemonic, uint32 index, address root) internal pure returns (address) {
        if (index < 10) return root;
        return _memberAddress(mnemonic, (index - 10) / 2);
    }
}
