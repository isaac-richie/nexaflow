// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {DeployBscMainnet} from "../script/DeployBscMainnet.s.sol";
import {DeployRwaanOracle} from "../script/DeployRwaanOracle.s.sol";

/// @dev Exposes the script's internal guards so each one can be proven to fire.
contract GuardHarness is DeployBscMainnet {
    function checkRoles(
        address admin,
        address operator,
        address treasury,
        address pauser,
        address root,
        bool allowEoaRoles,
        bool allowSharedControl
    ) external view {
        _checkRoles(admin, operator, treasury, pauser, root, allowEoaRoles, allowSharedControl);
    }

    function checkAdminDelay(uint48 d) external pure {
        _checkAdminDelay(d);
    }

    function checkedAdminDelay(uint256 d) external pure returns (uint48) {
        return _checkedAdminDelay(d);
    }

    function checkDeployer(
        address deployer,
        address admin,
        address operator,
        address treasury,
        address pauser,
        address root,
        bool allowSharedControl
    ) external pure {
        _checkDeployer(deployer, admin, operator, treasury, pauser, root, allowSharedControl);
    }

    function checkExpectedAddress(address predicted, address expected) external pure {
        _checkExpectedAddress(predicted, expected);
    }

    function checkRoleManifest(bytes32 actual, bytes32 expected) external pure {
        _checkRoleManifest(actual, expected);
    }

    function roleManifestHash(
        address admin,
        address operator,
        address treasury,
        address company,
        address pauser,
        address root,
        uint48 adminDelay
    ) external pure returns (bytes32) {
        return _roleManifestHash(admin, operator, treasury, company, pauser, root, adminDelay);
    }

    function checkCompanyWallet(address company, address treasury, address root) external pure {
        _checkCompanyWallet(company, treasury, root);
    }

    function minDelay() external pure returns (uint48) {
        return MIN_ADMIN_DELAY;
    }
}

contract MockSafeLike {
    address[] internal owners;
    uint256 internal threshold;

    constructor(uint256 ownerCount, uint256 configuredThreshold) {
        for (uint256 i; i < ownerCount; i++) {
            owners.push(address(uint160(0x1000 + i)));
        }
        threshold = configuredThreshold;
    }

    function getOwners() external view returns (address[] memory) {
        return owners;
    }

    function getThreshold() external view returns (uint256) {
        return threshold;
    }
}

contract NotASafe {}

contract OracleGuardHarness is DeployRwaanOracle {
    function checkTiming(uint256 period, uint256 feedMaxAge) external pure {
        _checkTiming(period, feedMaxAge);
    }
}

/// @notice The mainnet deployment guards.
///
///  A guard that has never been observed to reject anything is not a guard, it
///  is a comment. The testnet campaign already proved this pattern was worth
///  having: the six-decimal mock is retained purely so the 18-decimal check can
///  be seen failing. These do the same for the mainnet script.
contract BinaryMembershipV1MainnetDeployGuardsTest is Test {
    GuardHarness internal g;

    // Contract-shaped role holders, standing in for multisigs.
    address internal safeAdmin;
    address internal safeOperator;
    address internal safeTreasury;
    address internal safePauser;

    address internal constant EOA_ADMIN = address(0xA11CE);
    address internal constant EOA_PAUSER = address(0x9999);
    address internal constant ROOT = address(0x1);

    function setUp() public {
        g = new GuardHarness();

        safeAdmin = address(new MockSafeLike(3, 2));
        safeOperator = address(new MockSafeLike(3, 2));
        safeTreasury = address(new MockSafeLike(3, 2));
        safePauser = address(new MockSafeLike(3, 2));
    }

    // ── admin delay ──────────────────────────────────────────────────

    /// @notice The exact value the testnet script hardcodes must be refused
    ///         here. This is the mistake most likely to be copied forward.
    function test_Guard_RejectsZeroAdminDelay() public {
        vm.expectRevert(bytes("admin delay must not be zero on mainnet"));
        g.checkAdminDelay(0);
    }

    function test_Guard_RejectsAdminDelayBelowFloor() public {
        vm.expectRevert(bytes("admin delay below the safe floor"));
        g.checkAdminDelay(9 minutes);

        uint48 floor = g.minDelay();
        vm.expectRevert(bytes("admin delay below the safe floor"));
        g.checkAdminDelay(floor - 1);
    }

    function test_Guard_AcceptsDelayAtOrAboveFloor() public view {
        g.checkAdminDelay(g.minDelay());
        g.checkAdminDelay(7 days);
    }

    function test_Guard_RejectsAdminDelayThatWouldTruncate() public {
        vm.expectRevert(bytes("admin delay exceeds uint48"));
        g.checkedAdminDelay(uint256(type(uint48).max) + 1);
    }

    // ── role separation ──────────────────────────────────────────────

    function test_Guard_RejectsEoaRolesByDefault() public {
        vm.expectRevert(bytes("admin is an EOA - use a multisig or set ALLOW_EOA_ROLES"));
        g.checkRoles(EOA_ADMIN, safeOperator, safeTreasury, safePauser, ROOT, false, false);

        vm.expectRevert(bytes("operator is an EOA - use a multisig or set ALLOW_EOA_ROLES"));
        g.checkRoles(safeAdmin, address(0xB0B), safeTreasury, safePauser, ROOT, false, false);

        vm.expectRevert(bytes("treasury is an EOA - use a multisig or set ALLOW_EOA_ROLES"));
        g.checkRoles(safeAdmin, safeOperator, address(0xC0C), safePauser, ROOT, false, false);

        vm.expectRevert(bytes("pauser is an EOA - use a multisig or set ALLOW_EOA_ROLES"));
        g.checkRoles(safeAdmin, safeOperator, safeTreasury, EOA_PAUSER, ROOT, false, false);
    }

    /// @notice Hardware wallets are EOAs and a legitimate custody choice, so an
    ///         opt-out exists — but it has to be set on purpose.
    function test_Guard_EoaRolesAllowedOnlyWithExplicitOptOut() public {
        g.checkRoles(EOA_ADMIN, address(0xB0B), address(0xC0C), EOA_PAUSER, ROOT, true, false);

        vm.expectRevert(bytes("admin is an EOA - use a multisig or set ALLOW_EOA_ROLES"));
        g.checkRoles(EOA_ADMIN, safeOperator, safeTreasury, safePauser, ROOT, false, false);
    }

    /// @notice One key holding two roles defeats the separation the split
    ///         exists for. OPERATOR_ROLE can seed members into higher stages
    ///         fee-free, so admin-as-operator is a real concentration of power.
    function test_Guard_RejectsSharedRoleHolders() public {
        vm.expectRevert(bytes("admin and operator must differ"));
        g.checkRoles(EOA_ADMIN, EOA_ADMIN, address(0xC0C), EOA_PAUSER, ROOT, true, false);

        vm.expectRevert(bytes("admin and treasury must differ"));
        g.checkRoles(EOA_ADMIN, address(0xB0B), EOA_ADMIN, EOA_PAUSER, ROOT, true, false);

        vm.expectRevert(bytes("operator and treasury must differ"));
        g.checkRoles(EOA_ADMIN, address(0xB0B), address(0xB0B), EOA_PAUSER, ROOT, true, false);

        vm.expectRevert(bytes("operator and pauser must differ"));
        g.checkRoles(EOA_ADMIN, address(0xB0B), address(0xC0C), address(0xB0B), ROOT, true, false);

        vm.expectRevert(bytes("treasury and pauser must differ"));
        g.checkRoles(EOA_ADMIN, address(0xB0B), address(0xC0C), address(0xC0C), ROOT, true, false);

        vm.expectRevert(bytes("root and operator must differ"));
        g.checkRoles(EOA_ADMIN, address(0xB0B), address(0xC0C), EOA_PAUSER, address(0xB0B), true, false);
    }

    function test_Guard_AcceptsExactSharedControlPolicy() public view {
        g.checkRoles(EOA_ADMIN, EOA_ADMIN, address(0xC0C), EOA_ADMIN, ROOT, true, true);
        g.checkDeployer(EOA_ADMIN, EOA_ADMIN, EOA_ADMIN, address(0xC0C), EOA_ADMIN, ROOT, true);
    }

    function test_Guard_RejectsPartialSharedControlPolicy() public {
        vm.expectRevert(bytes("shared control requires admin=operator=pauser"));
        g.checkRoles(EOA_ADMIN, EOA_ADMIN, address(0xC0C), EOA_PAUSER, ROOT, true, true);

        vm.expectRevert(bytes("deployer must equal shared control address"));
        g.checkDeployer(address(0xD3), EOA_ADMIN, EOA_ADMIN, address(0xC0C), EOA_ADMIN, ROOT, true);
    }

    function test_Guard_RejectsZeroAddressRoles() public {
        vm.expectRevert(bytes("admin is zero"));
        g.checkRoles(address(0), address(0xB0B), address(0xC0C), EOA_PAUSER, ROOT, true, false);

        vm.expectRevert(bytes("root is zero"));
        g.checkRoles(EOA_ADMIN, address(0xB0B), address(0xC0C), EOA_PAUSER, address(0), true, false);
    }

    function test_Guard_AcceptsAWellFormedMultisigSetup() public view {
        g.checkRoles(safeAdmin, safeOperator, safeTreasury, safePauser, ROOT, false, false);
    }

    function test_Guard_RejectsContractThatIsNotSafeLike() public {
        address notSafe = address(new NotASafe());
        vm.expectRevert(bytes("admin is not a Safe-like multisig"));
        g.checkRoles(notSafe, safeOperator, safeTreasury, safePauser, ROOT, false, false);
    }

    function test_Guard_RejectsSingleSignerSafeLikeContract() public {
        address oneOfOne = address(new MockSafeLike(1, 1));
        vm.expectRevert(bytes("admin multisig needs at least two owners"));
        g.checkRoles(oneOfOne, safeOperator, safeTreasury, safePauser, ROOT, false, false);
    }

    function test_Guard_RejectsOneOfManyThreshold() public {
        address oneOfThree = address(new MockSafeLike(3, 1));
        vm.expectRevert(bytes("admin multisig threshold must be at least two"));
        g.checkRoles(oneOfThree, safeOperator, safeTreasury, safePauser, ROOT, false, false);
    }

    function test_Guard_RejectsDeployerRoleOverlap() public {
        vm.expectRevert(bytes("deployer and admin must differ"));
        g.checkDeployer(EOA_ADMIN, EOA_ADMIN, address(0xB0B), address(0xC0C), EOA_PAUSER, ROOT, false);

        vm.expectRevert(bytes("deployer and root must differ"));
        g.checkDeployer(ROOT, EOA_ADMIN, address(0xB0B), address(0xC0C), EOA_PAUSER, ROOT, false);
    }

    function test_Guard_RequiresIndependentExpectedAddress() public {
        address predicted = address(0x1234);

        vm.expectRevert(bytes("expected membership address is zero"));
        g.checkExpectedAddress(predicted, address(0));

        vm.expectRevert(bytes("predicted address does not match expected address"));
        g.checkExpectedAddress(predicted, address(0x5678));

        g.checkExpectedAddress(predicted, predicted);
    }

    function test_Guard_DeploymentSaltIsSourceControlled() public view {
        assertEq(g.deploymentSalt(), keccak256("BinaryMembershipV2:BSC_MAINNET:RWAAN:V2"));
    }

    function test_Guard_RoleManifestCommitsAllRoleInputs() public {
        bytes32 manifest = g.roleManifestHash(
            safeAdmin, safeOperator, safeTreasury, address(0xCAFE), safePauser, ROOT, uint48(10 minutes)
        );

        vm.expectRevert(bytes("expected role manifest is zero"));
        g.checkRoleManifest(manifest, bytes32(0));

        bytes32 changedPauser = g.roleManifestHash(
            safeAdmin, safeOperator, safeTreasury, address(0xCAFE), address(0xBEEF), ROOT, uint48(10 minutes)
        );
        vm.expectRevert(bytes("role manifest does not match expected hash"));
        g.checkRoleManifest(changedPauser, manifest);

        g.checkRoleManifest(manifest, manifest);
    }

    function test_Guard_CompanyWalletIsIndependentAndManifestBound() public {
        address company = address(0xCAFE);
        g.checkCompanyWallet(company, safeTreasury, ROOT);

        vm.expectRevert(bytes("company wallet is zero"));
        g.checkCompanyWallet(address(0), safeTreasury, ROOT);

        vm.expectRevert(bytes("company and treasury must differ"));
        g.checkCompanyWallet(safeTreasury, safeTreasury, ROOT);

        vm.expectRevert(bytes("company and root must differ"));
        g.checkCompanyWallet(ROOT, safeTreasury, ROOT);

        bytes32 original =
            g.roleManifestHash(safeAdmin, safeOperator, safeTreasury, company, safePauser, ROOT, uint48(10 minutes));
        bytes32 changed = g.roleManifestHash(
            safeAdmin, safeOperator, safeTreasury, address(0xBEEF), safePauser, ROOT, uint48(10 minutes)
        );
        assertTrue(original != changed, "company wallet missing from manifest");
    }
}

contract RwaanOracleMainnetDeployGuardsTest is Test {
    OracleGuardHarness internal guard;

    function setUp() public {
        guard = new OracleGuardHarness();
    }

    /// @notice The TWAP floor moved 2h -> 1h as a priced decision. It remains a
    ///         floor: a window an attacker only has to sustain for minutes is
    ///         barely better than a spot price on a pool this thin.
    function test_OracleGuardRejectsShortTwap() public {
        vm.expectRevert(bytes("TWAP period below production floor"));
        guard.checkTiming(1 hours - 1, 1 hours);

        vm.expectRevert(bytes("TWAP period below production floor"));
        guard.checkTiming(30 minutes, 1 hours);
    }

    /// @notice The BNB feed tolerance is capped on its own terms now, not tied
    ///         to the TWAP window. The feed updates roughly every 23 seconds,
    ///         so a multi-hour tolerance hides an outage rather than absorbing
    ///         one. The old 2h/3h production pairing is now correctly rejected.
    function test_OracleGuardRejectsLooseFeedTolerance() public {
        vm.expectRevert(bytes("BNB feed tolerance too loose"));
        guard.checkTiming(1 hours, 1 hours + 1);

        vm.expectRevert(bytes("BNB feed tolerance too loose"));
        guard.checkTiming(2 hours, 3 hours);
    }

    /// @notice A feed window SHORTER than the TWAP window is now valid. They
    ///         measure different things: the oracle rejects a stale feed
    ///         itself, while `maxPriceAge` governs TWAP age.
    function test_OracleGuardAcceptsProductionTiming() public view {
        guard.checkTiming(1 hours, 1 hours);
        guard.checkTiming(2 hours, 30 minutes);
    }
}
