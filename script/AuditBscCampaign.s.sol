// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {console2} from "forge-std/console2.sol";

import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {BscTestnetActors} from "./BscTestnetActors.sol";

contract AuditBscCampaign is BscTestnetActors {
    string internal campaignMnemonic;
    BinaryMembershipV1 internal membership;
    IERC20 internal token;
    uint32 internal walletCount;
    uint256 internal highestStage;
    uint256 internal sponsorFirstMask;
    address internal root;

    function run() external {
        _requireSupportedChain();

        campaignMnemonic = vm.envString("TESTNET_MNEMONIC");
        membership = BinaryMembershipV1(vm.envAddress("MEMBERSHIP_ADDRESS"));
        token = IERC20(vm.envAddress("MOCK_RWAAN_ADDRESS"));
        walletCount = uint32(vm.envOr("WALLET_END", uint256(100)));
        highestStage = vm.envOr("STAGE_END", uint256(5));
        sponsorFirstMask = vm.envOr("SPONSOR_FIRST_MASK", uint256(1));
        root = membership.designatedRoot();

        require(walletCount > 0 && walletCount <= 500, "invalid wallet count");
        require(highestStage < 6, "invalid stage end");
        require(membership.configured(), "not configured");
        require(membership.cycleGuardEnabled(), "cycle guard disabled");
        require(address(membership.asset()) == address(token), "token mismatch");
        require(IERC20Metadata(address(token)).decimals() == 18, "payment token decimals mismatch");
        require(membership.memberCount() == uint256(walletCount) + 1, "member count mismatch");

        (uint256 expectedFees, uint256 rootLedger) = _auditStages();
        (uint256 memberLedger, uint256 memberStageLedger) = _auditMembers();
        require(rootLedger + memberStageLedger == membership.totalPoolPaid(), "stage ledger mismatch");
        require(memberLedger + membership.getMember(root).totalEarned == membership.totalPoolPaid(), "pool mismatch");
        require(membership.totalPoolPaid() + membership.totalTreasuryPaid() == expectedFees, "fee conservation failed");
        require(token.balanceOf(address(membership)) == membership.pendingTreasury(), "treasury balance mismatch");

        console2.log("AUDIT PASS on chain       ", block.chainid);
        console2.log("member wallets            ", walletCount);
        console2.log("highest completed stage   ", highestStage);
        console2.log("expected fees (mRWAAN base)", expectedFees);
        console2.log("pool paid (mRWAAN base)    ", membership.totalPoolPaid());
        console2.log("treasury (mRWAAN base)     ", membership.pendingTreasury());
        console2.log("awards paid (mRWAAN base)  ", membership.totalAwardsPaid());
    }

    function _auditStages() internal view returns (uint256 expectedFees, uint256 rootLedger) {
        for (uint256 stageId; stageId <= highestStage; stageId++) {
            BinaryMembershipV1.StageConfig memory config = membership.getStageConfig(stageId);
            require(config.fee == _fee(stageId), "stage fee mismatch");
            require(config.rolloversForAward == _threshold(stageId), "award threshold mismatch");
            expectedFees += uint256(walletCount) * config.fee;
            rootLedger += membership.getStageMembership(root, stageId).stageEarnings;

            if ((sponsorFirstMask & (2 ** stageId)) == 0) {
                BinaryMembershipV1.StageMembership memory rootStage = membership.getStageMembership(root, stageId);
                require(rootStage.rolloverCount == uint256(walletCount) / config.treeSlots, "root rollover mismatch");
                require(rootStage.slotsFilledBelow == uint256(walletCount) % config.treeSlots, "root slots mismatch");
            }
        }
    }

    function _auditMembers() internal view returns (uint256 memberLedger, uint256 memberStageLedger) {
        for (uint32 index; index < walletCount; index++) {
            address member = _memberAddress(campaignMnemonic, index);
            BinaryMembershipV1.Member memory record = membership.getMember(member);
            require(record.active, "inactive member");
            uint256 walletLedger;
            for (uint256 stageId; stageId <= highestStage; stageId++) {
                BinaryMembershipV1.StageMembership memory stage = membership.getStageMembership(member, stageId);
                require(stage.enrolled, "missing stage enrollment");
                walletLedger += stage.stageEarnings;
                memberStageLedger += stage.stageEarnings;
            }
            require(record.totalEarned == walletLedger, "member earnings mismatch");
            memberLedger += walletLedger;
        }
    }

    function _fee(uint256 stageId) internal pure returns (uint256) {
        uint256 unit = 1e18;
        uint256[6] memory fees = [uint256(20 * unit), 60 * unit, 180 * unit, 540 * unit, 1_620 * unit, 4_860 * unit];
        return fees[stageId];
    }

    function _threshold(uint256 stageId) internal pure returns (uint256) {
        uint256[6] memory thresholds = [uint256(0), 10, 10, 10, 10, 8];
        return thresholds[stageId];
    }
}
