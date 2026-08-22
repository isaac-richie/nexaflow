// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {console2} from "forge-std/console2.sol";

import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {BinaryMembershipV3} from "../src/BinaryMembershipV3.sol";
import {MockAssetUsdPriceOracle} from "../src/MockAssetUsdPriceOracle.sol";
import {MockRWAAN18} from "../src/MockRWAAN18.sol";
import {BscTestnetActors} from "./BscTestnetActors.sol";

contract DeployBscTestnet is BscTestnetActors {
    function run() external returns (MockRWAAN18 token, BinaryMembershipV3 membership) {
        _requireSupportedChain();

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        string memory mnemonic = vm.envString("TESTNET_MNEMONIC");
        uint256 rootKey = _memberKey(mnemonic, ROOT_INDEX);
        uint256 operatorKey = _memberKey(mnemonic, OPERATOR_INDEX);
        address admin = vm.addr(deployerKey);
        address root = vm.addr(rootKey);
        address operator = vm.addr(operatorKey);
        address treasury = _memberAddress(mnemonic, TREASURY_INDEX);
        address company = _memberAddress(mnemonic, COMPANY_INDEX);
        address pauser = _memberAddress(mnemonic, PAUSER_INDEX);
        uint256 roleGas = vm.envOr("ROLE_GAS_WEI", uint256(1e15));

        vm.startBroadcast(deployerKey);
        token = new MockRWAAN18(admin);
        MockAssetUsdPriceOracle oracle = new MockAssetUsdPriceOracle(1 ether);
        membership =
            new BinaryMembershipV3(IERC20Metadata(address(token)), oracle, 2 hours, treasury, company, admin, 0, root);
        membership.grantRole(membership.OPERATOR_ROLE(), operator);
        membership.grantRole(membership.TREASURY_ROLE(), treasury);
        membership.grantRole(membership.PAUSER_ROLE(), pauser);
        _configureAndVerify(IERC20Metadata(address(token)), membership);
        membership.setCycleGuardEnabled(true);

        _fundIfNeeded(root, roleGas);
        _fundIfNeeded(operator, roleGas);
        _fundIfNeeded(treasury, roleGas);
        _fundIfNeeded(pauser, roleGas);
        vm.stopBroadcast();

        vm.startBroadcast(rootKey);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);
        vm.stopBroadcast();

        vm.startBroadcast(operatorKey);
        for (uint256 stageId = 1; stageId < 6; stageId++) {
            membership.enrollStageRoot(root, stageId);
        }
        vm.stopBroadcast();

        console2.log("BSC chain ID      ", block.chainid);
        console2.log("deployer/admin    ", admin);
        console2.log("mock RWAAN        ", address(token));
        console2.log("mock USD oracle   ", address(membership.priceOracle()));
        console2.log("payment decimals  ", token.decimals());
        console2.log("membership        ", address(membership));
        console2.log("designated root   ", root);
        console2.log("operator          ", operator);
        console2.log("treasury          ", treasury);
        console2.log("company           ", company);
        console2.log("pauser            ", pauser);
    }

    /// @dev Configuration is irreversible, so derive all display-unit amounts
    ///      from the selected token and verify every stored value before the
    ///      deployment transaction sequence is allowed to complete.
    function _configureAndVerify(IERC20Metadata token, BinaryMembershipV1 membership) internal {
        uint8 tokenDecimals = token.decimals();
        require(tokenDecimals == 18, "payment token must have 18 decimals");
        uint256 unit = 1e18; // USD denomination, not payment-token denomination

        uint256[6] memory fees = [uint256(20 * unit), 60 * unit, 180 * unit, 540 * unit, 1_620 * unit, 4_860 * unit];
        uint256[6] memory rewards = [uint256(5 * unit), 10 * unit, 25 * unit, 80 * unit, 250 * unit, 800 * unit];
        uint256[6] memory slots = [uint256(6), 14, 14, 14, 14, 14];
        uint256[6] memory depths = [uint256(2), 3, 3, 3, 3, 3];
        uint256[6] memory thresholds = [uint256(0), 10, 10, 10, 10, 8];

        membership.configureStages(fees, rewards, slots, depths, thresholds);

        for (uint256 stageId; stageId < 6; stageId++) {
            BinaryMembershipV1.StageConfig memory stored = membership.getStageConfig(stageId);
            require(stored.fee == fees[stageId], "stored fee mismatch");
            require(stored.nodeReward == rewards[stageId], "stored reward mismatch");
            require(stored.treeSlots == slots[stageId], "stored slots mismatch");
            require(stored.treeDepth == depths[stageId], "stored depth mismatch");
            require(stored.rolloversForAward == thresholds[stageId], "stored award threshold mismatch");
        }

        require(membership.getStageConfig(0).fee == 20 * unit, "$20 fee sanity check failed");
        require(membership.getStageConfig(5).fee == 4_860 * unit, "$4,860 fee sanity check failed");
    }

    function _fundIfNeeded(address recipient, uint256 targetBalance) internal {
        if (recipient.balance >= targetBalance) return;
        (bool sent,) = payable(recipient).call{value: targetBalance - recipient.balance}("");
        require(sent, "role gas funding failed");
    }
}
