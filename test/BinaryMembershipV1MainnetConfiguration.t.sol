// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {BinaryMembershipV3} from "../src/BinaryMembershipV3.sol";
import {MockAssetUsdPriceOracle} from "../src/MockAssetUsdPriceOracle.sol";
import {ConfigureBscMainnet} from "../script/ConfigureBscMainnet.s.sol";

contract BinaryMembershipV1MainnetConfigurationTest is Test {
    address internal constant BSC_RWAAN = 0xACB921bf2Dac2F7E8E101AAd9CA013d6Af5C648a;
    address internal constant TREASURY = address(0x2002);
    address internal constant COMPANY = address(0x2003);
    address internal constant ROOT = address(0x2004);
    bytes32 internal constant ROLE_MANIFEST_DOMAIN = keccak256("BinaryMembershipV3:BSC_MAINNET:ROLE_MANIFEST:V3");

    ConfigureBscMainnet internal configurator;
    BinaryMembershipV3 internal membership;
    MockAssetUsdPriceOracle internal oracle;

    function setUp() public {
        vm.chainId(56);
        vm.mockCall(BSC_RWAAN, abi.encodeWithSignature("decimals()"), abi.encode(uint8(18)));
        vm.mockCall(BSC_RWAAN, abi.encodeWithSignature("balanceOf(address)", address(0)), abi.encode(uint256(0)));

        oracle = new MockAssetUsdPriceOracle(0.0001 ether);
        membership = new BinaryMembershipV3(
            IERC20Metadata(BSC_RWAAN), oracle, 2 hours, TREASURY, COMPANY, address(this), uint48(10 minutes), ROOT
        );
        configurator = new ConfigureBscMainnet();

        vm.setEnv("MEMBERSHIP_ADDRESS", vm.toString(address(membership)));
        vm.setEnv("EXPECTED_MEMBERSHIP_ADDRESS", vm.toString(address(membership)));
        vm.setEnv("ADMIN_ADDRESS", vm.toString(address(this)));
        vm.setEnv("OPERATOR_ADDRESS", vm.toString(address(this)));
        vm.setEnv("TREASURY_ADDRESS", vm.toString(TREASURY));
        vm.setEnv("COMPANY_WALLET_ADDRESS", vm.toString(COMPANY));
        vm.setEnv("PAUSER_ADDRESS", vm.toString(address(this)));
        vm.setEnv("ROOT_ADDRESS", vm.toString(ROOT));
        vm.setEnv("ADMIN_DELAY_SECONDS", "600");
        vm.setEnv("PRICE_ORACLE_ADDRESS", vm.toString(address(oracle)));
        vm.setEnv("MAX_PRICE_AGE_SECONDS", "7200");
        bytes32 roleManifest = keccak256(
            abi.encode(
                ROLE_MANIFEST_DOMAIN,
                uint256(56),
                address(this),
                address(this),
                TREASURY,
                COMPANY,
                address(this),
                ROOT,
                uint48(10 minutes)
            )
        );
        vm.setEnv("EXPECTED_ROLE_MANIFEST_HASH", vm.toString(roleManifest));

        // The verifier asks for this contract's exact balance, not address(0).
        vm.mockCall(
            BSC_RWAAN, abi.encodeWithSignature("balanceOf(address)", address(membership)), abi.encode(uint256(0))
        );
    }

    function test_SafeBatchConfiguresAndVerifiesEveryLaunchInvariant() public {
        ConfigureBscMainnet.SafeAction[5] memory actions = configurator.printCalldata();

        for (uint256 i; i < actions.length; i++) {
            assertEq(actions[i].target, address(membership));
            assertEq(actions[i].value, 0);
        }
        assertEq(bytes4(actions[0].data), membership.grantRole.selector);
        assertEq(bytes4(actions[1].data), membership.grantRole.selector);
        assertEq(bytes4(actions[2].data), membership.grantRole.selector);
        assertEq(bytes4(actions[3].data), membership.setCycleGuardEnabled.selector);
        assertEq(bytes4(actions[4].data), membership.configureStages.selector);

        _execute(actions, actions.length);

        assertTrue(configurator.verify());
        assertTrue(membership.hasRole(membership.OPERATOR_ROLE(), address(this)));
        assertTrue(membership.hasRole(membership.TREASURY_ROLE(), TREASURY));
        assertTrue(membership.hasRole(membership.PAUSER_ROLE(), address(this)));
        assertEq(membership.companyWallet(), COMPANY);
        assertEq(membership.getStageConfig(0).rolloversForAward, 0);
        assertEq(membership.getStageConfig(1).rolloversForAward, 10);
        assertEq(membership.getStageConfig(4).rolloversForAward, 10);
        assertEq(membership.getStageConfig(5).rolloversForAward, 8);
    }

    function test_VerifierRejectsConfigurationWithoutCycleGuard() public {
        ConfigureBscMainnet.SafeAction[5] memory actions = configurator.printCalldata();
        actions[3] = actions[4];
        _execute(actions, 4);

        vm.expectRevert(bytes("cycle guard disabled"));
        configurator.verify();
    }

    function test_VerifierRejectsChangedStageValues() public {
        ConfigureBscMainnet.SafeAction[5] memory actions = configurator.printCalldata();
        _execute(actions, actions.length);

        membership.updateStageFee(1, 61 ether, 10 ether);

        vm.expectRevert(bytes("stored fee mismatch"));
        configurator.verify();
    }

    function test_CalldataGeneratorRefusesAConfiguredContract() public {
        ConfigureBscMainnet.SafeAction[5] memory actions = configurator.printCalldata();
        _execute(actions, actions.length);

        vm.expectRevert(bytes("membership already configured"));
        configurator.printCalldata();
    }

    function _execute(ConfigureBscMainnet.SafeAction[5] memory actions, uint256 count) internal {
        for (uint256 i; i < count; i++) {
            (bool success, bytes memory returnData) = actions[i].target.call(actions[i].data);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(returnData, 0x20), mload(returnData))
                }
            }
        }
    }
}
