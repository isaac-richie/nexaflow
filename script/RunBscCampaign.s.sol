// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console2} from "forge-std/console2.sol";

import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {BinaryMembershipV2} from "../src/BinaryMembershipV2.sol";
import {BscTestnetActors} from "./BscTestnetActors.sol";

contract RunBscCampaign is BscTestnetActors {
    string internal campaignMnemonic;
    BinaryMembershipV2 internal membership;
    IERC20 internal token;
    uint32 internal walletStart;
    uint32 internal walletEnd;
    uint256 internal stageStart;
    uint256 internal stageEnd;
    uint256 internal sponsorFirstMask;
    address internal root;

    function run() external {
        _requireSupportedChain();

        campaignMnemonic = vm.envString("TESTNET_MNEMONIC");
        membership = BinaryMembershipV2(vm.envAddress("MEMBERSHIP_ADDRESS"));
        token = IERC20(vm.envAddress("MOCK_RWAAN_ADDRESS"));
        walletStart = uint32(vm.envOr("WALLET_START", uint256(0)));
        walletEnd = uint32(vm.envOr("WALLET_END", uint256(100)));
        stageStart = vm.envOr("STAGE_START", uint256(0));
        stageEnd = vm.envOr("STAGE_END", uint256(5));
        sponsorFirstMask = vm.envOr("SPONSOR_FIRST_MASK", uint256(1));
        root = membership.designatedRoot();

        require(walletStart < walletEnd && walletEnd <= 500, "invalid wallet range");
        require(stageStart <= stageEnd && stageEnd < 6, "invalid stage range");
        require(address(membership.asset()) == address(token), "token mismatch");

        _approveWallets();

        if (stageStart == 0) {
            _registerWallets();
        }

        uint256 firstHigherStage = stageStart == 0 ? 1 : stageStart;
        for (uint256 stageId = firstHigherStage; stageId <= stageEnd; stageId++) {
            _joinStage(stageId);
            console2.log("completed stage", stageId);
        }
    }

    function _approveWallets() internal {
        (uint256 largestQuotedFee,,,) = membership.quoteStagePayment(stageEnd);
        for (uint32 index = walletStart; index < walletEnd; index++) {
            address member = _memberAddress(campaignMnemonic, index);
            if (token.allowance(member, address(membership)) >= largestQuotedFee) continue;
            vm.startBroadcast(_memberKey(campaignMnemonic, index));
            token.approve(address(membership), type(uint256).max);
            vm.stopBroadcast();
        }
    }

    function _registerWallets() internal {
        for (uint32 index = walletStart; index < walletEnd; index++) {
            address member = _memberAddress(campaignMnemonic, index);
            if (membership.getMember(member).active) continue;
            address sponsor = _sponsorFor(campaignMnemonic, index, root);
            (address parent, BinaryMembershipV1.Side side) = (sponsorFirstMask & 1) != 0
                ? membership.findPlacementSlot(sponsor, 0)
                : membership.findOpenSlot(root, 0);

            vm.startBroadcast(_memberKey(campaignMnemonic, index));
            (uint256 maximumPayment,,,) = membership.quoteStagePayment(0);
            membership.registerWithMaxPayment(sponsor, parent, side, maximumPayment, block.timestamp + 1 hours);
            vm.stopBroadcast();
            _logProgress("registered", index, walletEnd);
        }
    }

    function _joinStage(uint256 stageId) internal {
        for (uint32 index = walletStart; index < walletEnd; index++) {
            address member = _memberAddress(campaignMnemonic, index);
            if (membership.getStageMembership(member, stageId).enrolled) continue;
            address sponsor = membership.getMember(member).sponsor;
            (address parent, BinaryMembershipV1.Side side) = (sponsorFirstMask & (2 ** stageId)) != 0
                ? membership.findPlacementSlot(sponsor, stageId)
                : membership.findOpenSlot(root, stageId);

            vm.startBroadcast(_memberKey(campaignMnemonic, index));
            (uint256 maximumPayment,,,) = membership.quoteStagePayment(stageId);
            membership.joinStageWithMaxPayment(
                stageId, parent, side, maximumPayment, block.timestamp + 1 hours
            );
            vm.stopBroadcast();
            _logProgress("joined", index, walletEnd);
        }
    }

    function _logProgress(string memory action, uint32 index, uint32 end) internal pure {
        if ((index + 1) % 10 == 0 || index + 1 == end) {
            console2.log(action, uint256(index + 1));
        }
    }
}
