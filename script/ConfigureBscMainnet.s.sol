// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {console2} from "forge-std/console2.sol";

import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {BinaryMembershipV4} from "../src/BinaryMembershipV4.sol";

/// @title V4 BSC mainnet configuration calldata generator and verifier
/// @notice This script never broadcasts. The default-admin holder executes all
///         generated calls atomically, then runs verify before root launch.
contract ConfigureBscMainnet is Script {
    address internal constant BSC_USDT = 0x55d398326f99059fF775485246999027B3197955;
    bytes32 internal constant EXPECTED_USDT_RUNTIME_HASH =
        0x97a48aa4c129657440dafdacd4c836389734d28cc4a0ca7403e68da660a74a59;
    uint256 internal constant BSC_MAINNET = 56;
    uint256 internal constant ACTION_COUNT = 5;
    bytes32 internal constant ROLE_MANIFEST_DOMAIN = keccak256("BinaryMembershipV4:BSC_MAINNET:ROLE_MANIFEST:V4");

    struct SafeAction {
        address target;
        uint256 value;
        bytes data;
    }

    /// @notice Execute the five configuration calls when the explicitly
    ///         configured shared controller is an EOA held by DEPLOYER_PRIVATE_KEY.
    /// @dev Safe deployments must use printCalldata() and execute the returned
    ///      calls through the Safe instead. This path refuses to run unless
    ///      both deliberate EOA/shared-control policy switches are enabled.
    function configureFromSharedController() external {
        require(vm.envOr("ALLOW_EOA_ROLES", false), "EOA role policy is disabled");
        require(vm.envOr("ALLOW_SHARED_CONTROL_ADDRESS", false), "shared control policy is disabled");

        BinaryMembershipV4 membership = _membership();
        address admin = vm.envAddress("ADMIN_ADDRESS");
        uint256 adminKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        require(vm.addr(adminKey) == admin, "deployer key is not the admin");
        _assertDeploymentState(membership);
        require(!membership.configured() && !membership.cycleGuardEnabled(), "already configured");
        require(membership.memberCount() == 0, "members exist before configuration");

        address operator = vm.envAddress("OPERATOR_ADDRESS");
        address treasuryRole = vm.envAddress("TREASURY_ADDRESS");
        address pauser = vm.envAddress("PAUSER_ADDRESS");
        require(!membership.hasRole(membership.OPERATOR_ROLE(), operator), "operator already granted");
        require(!membership.hasRole(membership.TREASURY_ROLE(), treasuryRole), "treasury already granted");
        require(!membership.hasRole(membership.PAUSER_ROLE(), pauser), "pauser already granted");
        (
            uint256[6] memory fees,
            uint256[6] memory rewards,
            uint256[6] memory slots,
            uint256[6] memory depths,
            uint256[6] memory thresholds
        ) = _stageValues();

        vm.startBroadcast(adminKey);
        membership.grantRole(membership.OPERATOR_ROLE(), operator);
        membership.grantRole(membership.TREASURY_ROLE(), treasuryRole);
        membership.grantRole(membership.PAUSER_ROLE(), pauser);
        membership.setCycleGuardEnabled(true);
        membership.configureStages(fees, rewards, slots, depths, thresholds);
        vm.stopBroadcast();
    }

    /// @notice Continue a configuration broadcast after an RPC interruption.
    /// @dev Every call is conditional and the immutable stage setup is sent
    ///      only while unconfigured, so rerunning this function cannot alter a
    ///      completed launch configuration.
    function resumeFromSharedController() external {
        require(vm.envOr("ALLOW_EOA_ROLES", false), "EOA role policy is disabled");
        require(vm.envOr("ALLOW_SHARED_CONTROL_ADDRESS", false), "shared control policy is disabled");

        BinaryMembershipV4 membership = _membership();
        address admin = vm.envAddress("ADMIN_ADDRESS");
        uint256 adminKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        require(vm.addr(adminKey) == admin, "deployer key is not the admin");
        _assertDeploymentState(membership);
        require(membership.memberCount() == 0, "members exist before configuration");

        address operator = vm.envAddress("OPERATOR_ADDRESS");
        address treasuryRole = vm.envAddress("TREASURY_ADDRESS");
        address pauser = vm.envAddress("PAUSER_ADDRESS");
        (
            uint256[6] memory fees,
            uint256[6] memory rewards,
            uint256[6] memory slots,
            uint256[6] memory depths,
            uint256[6] memory thresholds
        ) = _stageValues();

        vm.startBroadcast(adminKey);
        if (!membership.hasRole(membership.OPERATOR_ROLE(), operator)) {
            membership.grantRole(membership.OPERATOR_ROLE(), operator);
        }
        if (!membership.hasRole(membership.TREASURY_ROLE(), treasuryRole)) {
            membership.grantRole(membership.TREASURY_ROLE(), treasuryRole);
        }
        if (!membership.hasRole(membership.PAUSER_ROLE(), pauser)) {
            membership.grantRole(membership.PAUSER_ROLE(), pauser);
        }
        if (!membership.cycleGuardEnabled()) membership.setCycleGuardEnabled(true);
        if (!membership.configured()) membership.configureStages(fees, rewards, slots, depths, thresholds);
        vm.stopBroadcast();
    }

    function printCalldata() external view returns (SafeAction[ACTION_COUNT] memory actions) {
        BinaryMembershipV4 membership = _membership();
        address operator = vm.envAddress("OPERATOR_ADDRESS");
        address treasuryRole = vm.envAddress("TREASURY_ADDRESS");
        address pauser = vm.envAddress("PAUSER_ADDRESS");
        _assertDeploymentState(membership);
        require(!membership.configured() && !membership.cycleGuardEnabled(), "already configured");
        require(membership.memberCount() == 0, "members exist before configuration");
        require(!membership.hasRole(membership.OPERATOR_ROLE(), operator), "operator already granted");
        require(!membership.hasRole(membership.TREASURY_ROLE(), treasuryRole), "treasury already granted");
        require(!membership.hasRole(membership.PAUSER_ROLE(), pauser), "pauser already granted");

        (
            uint256[6] memory fees,
            uint256[6] memory rewards,
            uint256[6] memory slots,
            uint256[6] memory depths,
            uint256[6] memory thresholds
        ) = _stageValues();
        actions[0] = SafeAction(
            address(membership), 0, abi.encodeCall(membership.grantRole, (membership.OPERATOR_ROLE(), operator))
        );
        actions[1] = SafeAction(
            address(membership), 0, abi.encodeCall(membership.grantRole, (membership.TREASURY_ROLE(), treasuryRole))
        );
        actions[2] = SafeAction(
            address(membership), 0, abi.encodeCall(membership.grantRole, (membership.PAUSER_ROLE(), pauser))
        );
        actions[3] = SafeAction(address(membership), 0, abi.encodeCall(membership.setCycleGuardEnabled, (true)));
        actions[4] = SafeAction(
            address(membership),
            0,
            abi.encodeCall(membership.configureStages, (fees, rewards, slots, depths, thresholds))
        );

        console2.log("ADMIN CONFIGURATION: execute all five calls atomically and in order");
        for (uint256 i; i < ACTION_COUNT; ++i) {
            console2.log("action", i + 1);
            console2.log("target", actions[i].target);
            console2.log("value", actions[i].value);
            console2.logBytes(actions[i].data);
        }
    }

    function verify() external view returns (bool) {
        BinaryMembershipV4 membership = _membership();
        _assertDeploymentState(membership);
        require(
            membership.configured() && membership.cycleGuardEnabled() && !membership.paused(), "launch state mismatch"
        );
        require(membership.memberCount() == 0, "member joined before audit");
        require(membership.hasRole(membership.OPERATOR_ROLE(), vm.envAddress("OPERATOR_ADDRESS")), "operator missing");
        require(membership.hasRole(membership.TREASURY_ROLE(), vm.envAddress("TREASURY_ADDRESS")), "treasury missing");
        require(membership.hasRole(membership.PAUSER_ROLE(), vm.envAddress("PAUSER_ADDRESS")), "pauser missing");

        (
            uint256[6] memory fees,
            uint256[6] memory rewards,
            uint256[6] memory slots,
            uint256[6] memory depths,
            uint256[6] memory thresholds
        ) = _stageValues();
        for (uint256 stageId; stageId < 6; ++stageId) {
            BinaryMembershipV1.StageConfig memory stored = membership.getStageConfig(stageId);
            require(stored.fee == fees[stageId] && stored.nodeReward == rewards[stageId], "stored fee/reward mismatch");
            require(
                stored.treeSlots == slots[stageId] && stored.treeDepth == depths[stageId], "stored geometry mismatch"
            );
            require(stored.rolloversForAward == thresholds[stageId], "stored threshold mismatch");
            require(
                !membership.stageClosed(stageId) && membership.stageAnchor(stageId) == address(0),
                "unexpected stage state"
            );
        }
        require(membership.pendingTreasury() == 0, "treasury nonzero before launch");
        require(IERC20Metadata(BSC_USDT).balanceOf(address(membership)) == 0, "USDT balance nonzero before launch");
        return true;
    }

    function _membership() internal view returns (BinaryMembershipV4 membership) {
        require(block.chainid == BSC_MAINNET, "not BSC mainnet (expected chain 56)");
        address membershipAddress = vm.envAddress("MEMBERSHIP_ADDRESS");
        require(
            membershipAddress == vm.envAddress("EXPECTED_MEMBERSHIP_ADDRESS"),
            "membership does not match expected address"
        );
        require(membershipAddress.code.length > 0, "membership has no code");
        return BinaryMembershipV4(membershipAddress);
    }

    function _assertDeploymentState(BinaryMembershipV4 membership) internal view {
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address operator = vm.envAddress("OPERATOR_ADDRESS");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address company = vm.envAddress("COMPANY_WALLET_ADDRESS");
        address pauser = vm.envAddress("PAUSER_ADDRESS");
        address root = vm.envAddress("ROOT_ADDRESS");
        uint256 rawDelay = vm.envUint("ADMIN_DELAY_SECONDS");
        require(rawDelay <= type(uint48).max && rawDelay >= 10 minutes, "invalid admin delay");
        require(address(membership.asset()) == BSC_USDT, "wrong payment token");
        require(keccak256(BSC_USDT.code) == EXPECTED_USDT_RUNTIME_HASH, "USDT runtime hash changed");
        require(IERC20Metadata(BSC_USDT).decimals() == 18, "USDT must have 18 decimals");
        require(membership.defaultAdmin() == admin && membership.treasury() == treasury, "admin/treasury mismatch");
        require(membership.companyWallet() == company && company != treasury && company != root, "company mismatch");
        require(
            membership.designatedRoot() == root && membership.defaultAdminDelay() == uint48(rawDelay),
            "root/delay mismatch"
        );
        require(
            _roleManifestHash(admin, operator, treasury, company, pauser, root, uint48(rawDelay))
                == vm.envBytes32("EXPECTED_ROLE_MANIFEST_HASH"),
            "role manifest mismatch"
        );
    }

    function _roleManifestHash(
        address admin,
        address operator,
        address treasury,
        address company,
        address pauser,
        address root,
        uint48 delay
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(ROLE_MANIFEST_DOMAIN, BSC_MAINNET, admin, operator, treasury, company, pauser, root, delay)
        );
    }

    function _stageValues()
        internal
        pure
        returns (
            uint256[6] memory fees,
            uint256[6] memory rewards,
            uint256[6] memory slots,
            uint256[6] memory depths,
            uint256[6] memory thresholds
        )
    {
        uint256 unit = 1e18;
        fees = [uint256(20 * unit), 60 * unit, 180 * unit, 540 * unit, 1_620 * unit, 4_860 * unit];
        rewards = [uint256(5 * unit), 10 * unit, 25 * unit, 80 * unit, 250 * unit, 800 * unit];
        slots = [uint256(6), 14, 14, 14, 14, 14];
        depths = [uint256(2), 3, 3, 3, 3, 3];
        thresholds = [uint256(0), 10, 10, 10, 10, 8];
    }
}
