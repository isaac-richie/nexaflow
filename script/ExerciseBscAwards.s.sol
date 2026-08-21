// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";

import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {BscTestnetActors} from "./BscTestnetActors.sol";

/// @notice Grants one small award at every eligible paid stage after the
///         140-wallet extension. Safe to resume: ineligible stages are skipped.
contract ExerciseBscAwards is BscTestnetActors {
    function run() external {
        _requireSupportedChain();

        string memory mnemonic = vm.envString("TESTNET_MNEMONIC");
        BinaryMembershipV1 membership = BinaryMembershipV1(vm.envAddress("MEMBERSHIP_ADDRESS"));
        uint256 operatorKey = _memberKey(mnemonic, OPERATOR_INDEX);
        address root = membership.designatedRoot();
        uint256 amount = vm.envOr("TEST_AWARD_AMOUNT", uint256(1e18));

        require(membership.getStageConfig(0).rolloversForAward == 0, "$20 award unexpectedly enabled");

        for (uint256 stageId = 1; stageId < 6; stageId++) {
            (,,, uint256 nextMilestone, bool eligible) = membership.getAwardInfo(root, stageId);
            if (!eligible) {
                console2.log("stage not currently eligible", stageId);
                continue;
            }

            vm.startBroadcast(operatorKey);
            membership.grantPhysicalAward(root, stageId, amount);
            vm.stopBroadcast();

            (uint256 totalAwarded, uint256 lastAwarded,, uint256 followingMilestone, bool eligibleAgain) =
                membership.getAwardInfo(root, stageId);
            require(lastAwarded == nextMilestone, "award milestone not consumed");
            require(!eligibleAgain, "repeat award unlocked early");
            console2.log("award granted at stage", stageId);
            console2.log("stage total awarded     ", totalAwarded);
            console2.log("next milestone          ", followingMilestone);
        }
    }
}
