// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {console2} from "forge-std/console2.sol";

import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {BinaryMembershipV3} from "../src/BinaryMembershipV3.sol";

/// @title Admin calldata generator and verifier for BSC mainnet configuration
/// @notice This script never broadcasts and never reads a private key. It
///         generates the exact five calls that the admin role holder executes,
///         then independently verifies every resulting field. The guard is
///         enabled before one-time stage configuration so sequential EOA calls
///         never leave an initialized but unguarded membership contract.
///         Keeping configuration out of the deployment transaction prevents a
///         partially configured retry without leaving humans to hand-encode
///         the one-time stage arrays.
contract ConfigureBscMainnet is Script {
    address internal constant BSC_RWAAN = 0xACB921bf2Dac2F7E8E101AAd9CA013d6Af5C648a;
    uint256 internal constant BSC_MAINNET = 56;
    uint256 internal constant ACTION_COUNT = 5;
    bytes32 internal constant ROLE_MANIFEST_DOMAIN = keccak256("BinaryMembershipV3:BSC_MAINNET:ROLE_MANIFEST:V3");

    struct SafeAction {
        address target;
        uint256 value;
        bytes data;
    }

    /// @notice Print and return the exact admin calls. Execute in this order.
    function printCalldata() external view returns (SafeAction[ACTION_COUNT] memory actions) {
        BinaryMembershipV3 membership = _membership();
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address operator = vm.envAddress("OPERATOR_ADDRESS");
        address treasuryRole = vm.envAddress("TREASURY_ADDRESS");
        address company = vm.envAddress("COMPANY_WALLET_ADDRESS");
        address pauser = vm.envAddress("PAUSER_ADDRESS");

        _assertDeploymentState(membership, admin, operator, treasuryRole, company, pauser);
        require(!membership.configured(), "membership already configured");
        require(!membership.cycleGuardEnabled(), "cycle guard already enabled");
        require(membership.memberCount() == 0, "members exist before configuration");
        require(!membership.hasRole(membership.OPERATOR_ROLE(), operator), "operator role already granted");
        require(!membership.hasRole(membership.TREASURY_ROLE(), treasuryRole), "treasury role already granted");
        require(!membership.hasRole(membership.PAUSER_ROLE(), pauser), "pauser role already granted");

        (
            uint256[6] memory fees,
            uint256[6] memory rewards,
            uint256[6] memory slots,
            uint256[6] memory depths,
            uint256[6] memory thresholds
        ) = _stageValues();

        actions[0] = SafeAction({
            target: address(membership),
            value: 0,
            data: abi.encodeCall(membership.grantRole, (membership.OPERATOR_ROLE(), operator))
        });
        actions[1] = SafeAction({
            target: address(membership),
            value: 0,
            data: abi.encodeCall(membership.grantRole, (membership.TREASURY_ROLE(), treasuryRole))
        });
        actions[2] = SafeAction({
            target: address(membership),
            value: 0,
            data: abi.encodeCall(membership.grantRole, (membership.PAUSER_ROLE(), pauser))
        });
        actions[3] = SafeAction({
            target: address(membership), value: 0, data: abi.encodeCall(membership.setCycleGuardEnabled, (true))
        });
        actions[4] = SafeAction({
            target: address(membership),
            value: 0,
            data: abi.encodeCall(membership.configureStages, (fees, rewards, slots, depths, thresholds))
        });

        console2.log("ADMIN CONFIGURATION: execute all five calls in order");
        for (uint256 i; i < ACTION_COUNT; i++) {
            console2.log("action", i + 1);
            console2.log("target", actions[i].target);
            console2.log("value", actions[i].value);
            console2.log("data");
            console2.logBytes(actions[i].data);
        }
    }

    /// @notice Post-configuration audit. Reverts on the first mismatch.
    ///         Run immediately after configuration and before root enrollment.
    function verify() external view returns (bool) {
        BinaryMembershipV3 membership = _membership();
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address operator = vm.envAddress("OPERATOR_ADDRESS");
        address treasuryRole = vm.envAddress("TREASURY_ADDRESS");
        address company = vm.envAddress("COMPANY_WALLET_ADDRESS");
        address pauser = vm.envAddress("PAUSER_ADDRESS");

        _assertDeploymentState(membership, admin, operator, treasuryRole, company, pauser);
        require(membership.configured(), "stages not configured");
        require(membership.cycleGuardEnabled(), "cycle guard disabled");
        require(!membership.paused(), "membership unexpectedly paused");
        require(membership.memberCount() == 0, "member joined before configuration audit");
        require(membership.hasRole(membership.OPERATOR_ROLE(), operator), "operator role missing");
        require(membership.hasRole(membership.TREASURY_ROLE(), treasuryRole), "treasury role missing");
        require(membership.hasRole(membership.PAUSER_ROLE(), pauser), "pauser role missing");

        (
            uint256[6] memory fees,
            uint256[6] memory rewards,
            uint256[6] memory slots,
            uint256[6] memory depths,
            uint256[6] memory thresholds
        ) = _stageValues();

        for (uint256 stageId; stageId < 6; stageId++) {
            BinaryMembershipV1.StageConfig memory stored = membership.getStageConfig(stageId);
            require(stored.fee == fees[stageId], "stored fee mismatch");
            require(stored.nodeReward == rewards[stageId], "stored reward mismatch");
            require(stored.treeSlots == slots[stageId], "stored slots mismatch");
            require(stored.treeDepth == depths[stageId], "stored depth mismatch");
            require(stored.rolloversForAward == thresholds[stageId], "stored threshold mismatch");
            require(!membership.stageClosed(stageId), "stage unexpectedly closed");
            require(membership.stageAnchor(stageId) == address(0), "stage root seeded before audit");
        }

        require(membership.pendingTreasury() == 0, "treasury nonzero before launch");
        require(IERC20Metadata(BSC_RWAAN).balanceOf(address(membership)) == 0, "token balance nonzero before launch");
        return true;
    }

    function _membership() internal view returns (BinaryMembershipV3 membership) {
        require(block.chainid == BSC_MAINNET, "not BSC mainnet (expected chain 56)");
        address membershipAddress = vm.envAddress("MEMBERSHIP_ADDRESS");
        address expectedAddress = vm.envAddress("EXPECTED_MEMBERSHIP_ADDRESS");
        require(membershipAddress == expectedAddress, "membership does not match expected address");
        require(membershipAddress.code.length > 0, "membership has no code");
        membership = BinaryMembershipV3(membershipAddress);
    }

    function _assertDeploymentState(
        BinaryMembershipV3 membership,
        address admin,
        address operator,
        address treasuryRole,
        address company,
        address pauser
    ) internal view {
        address root = vm.envAddress("ROOT_ADDRESS");
        uint256 rawAdminDelay = vm.envUint("ADMIN_DELAY_SECONDS");
        require(rawAdminDelay <= type(uint48).max, "admin delay exceeds uint48");
        uint48 adminDelay = uint48(rawAdminDelay);
        require(adminDelay >= 10 minutes, "admin transfer delay below floor");

        require(address(membership.asset()) == BSC_RWAAN, "wrong payment token");
        require(address(membership.priceOracle()) == vm.envAddress("PRICE_ORACLE_ADDRESS"), "wrong price oracle");
        require(membership.maxPriceAge() == vm.envUint("MAX_PRICE_AGE_SECONDS"), "wrong max price age");
        (uint256 priceUsd18,) = membership.latestAssetPriceUsd();
        require(priceUsd18 > 0, "price oracle not ready");
        require(membership.defaultAdmin() == admin, "wrong default admin");
        require(membership.treasury() == treasuryRole, "wrong treasury address");
        require(membership.companyWallet() == company, "wrong company wallet");
        require(company != treasuryRole, "company and treasury must differ");
        require(membership.designatedRoot() == root, "wrong designated root");
        require(membership.defaultAdminDelay() == adminDelay, "wrong admin transfer delay");
        require(IERC20Metadata(BSC_RWAAN).decimals() == 18, "payment token must have 18 decimals");

        bytes32 expectedManifest = vm.envBytes32("EXPECTED_ROLE_MANIFEST_HASH");
        require(expectedManifest != bytes32(0), "expected role manifest is zero");
        require(
            _roleManifestHash(admin, operator, treasuryRole, company, pauser, root, adminDelay) == expectedManifest,
            "role manifest does not match expected hash"
        );
    }

    function _roleManifestHash(
        address admin,
        address operator,
        address treasury,
        address company,
        address pauser,
        address root,
        uint48 adminDelay
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(ROLE_MANIFEST_DOMAIN, BSC_MAINNET, admin, operator, treasury, company, pauser, root, adminDelay)
        );
    }

    function _stageValues()
        internal
        view
        returns (
            uint256[6] memory fees,
            uint256[6] memory rewards,
            uint256[6] memory slots,
            uint256[6] memory depths,
            uint256[6] memory thresholds
        )
    {
        // Configuration is USD-denominated at 18 decimals. V2 converts these
        // values into RWAAN from the live oracle during each paid enrollment.
        uint256 unit = 1e18;

        fees = [uint256(20 * unit), 60 * unit, 180 * unit, 540 * unit, 1_620 * unit, 4_860 * unit];
        rewards = [uint256(5 * unit), 10 * unit, 25 * unit, 80 * unit, 250 * unit, 800 * unit];
        slots = [uint256(6), 14, 14, 14, 14, 14];
        depths = [uint256(2), 3, 3, 3, 3, 3];
        thresholds = [uint256(0), 10, 10, 10, 10, 8];
    }
}
