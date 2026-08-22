// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {console2} from "forge-std/console2.sol";

import {BinaryMembershipV3} from "../src/BinaryMembershipV3.sol";
import {IAssetUsdPriceOracle} from "../src/interfaces/IAssetUsdPriceOracle.sol";
import {PancakeV2RwaanUsdOracle} from "../src/PancakeV2RwaanUsdOracle.sol";

/// @dev The production policy is deliberately Safe-shaped rather than merely
///      "has bytecode". Any contract can have code; these two calls prove the
///      configured holder exposes the ownership and threshold controls the
///      runbook relies on.
interface ISafeLike {
    function getOwners() external view returns (address[] memory);
    function getThreshold() external view returns (uint256);
}

/// @title BSC mainnet deployment
///
/// @notice Separate from the testnet script on purpose. The testnet script
///         deploys a mock token, uses a mnemonic for every role, and passes an
///         admin delay of zero — all correct there and all wrong here. Copying
///         it and editing values is exactly how those wrong defaults reach
///         production, so this script cannot be run against a test setup and
///         the testnet script cannot be run against mainnet.
///
/// Constructor-time decisions are guarded here. The one-time stage setup is
/// generated and verified by `ConfigureBscMainnet.s.sol`; it is intentionally
/// not executed with the deployer key.
///
///  - RWAAN and its USD oracle are pinned by ADDRESS. Decimals and live supply are
///    checked as corroboration, never as identification — any contract can
///    claim to be RWAAN by name or symbol.
///  - The default-admin TRANSFER delay must clear a real floor. This delay does
///    not timelock calls made by the current admin; the admin Safe/Delay Module
///    is what protects runtime administration.
///  - Privileged roles must be Safe-like multisigs unless an operator
///    deliberately opts out for EOAs. A second explicit policy switch permits
///    exactly one shared control address for deployer/admin/operator/pauser;
///    treasury and the economic root must remain separate.
///  - Deployment uses a source-controlled CREATE2 salt, an independently
///    supplied expected address and a role-manifest hash. A changed input or
///    RPC retry cannot silently create another "canonical" deployment/config.
contract DeployBscMainnet is Script {
    struct DeploymentInputs {
        address admin;
        address operator;
        address treasury;
        address company;
        address pauser;
        address root;
        uint48 adminDelay;
    }

    /// @dev Rawli Analytics (RWAAN). Pinned by address.
    address internal constant BSC_RWAAN = 0xACB921bf2Dac2F7E8E101AAd9CA013d6Af5C648a;
    address internal constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address internal constant RWAAN_WBNB_PAIR = 0xA285059BBc89Fe9B43414D098318675462aaa3e6;
    address internal constant BNB_USD_FEED = 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE;

    uint256 internal constant BSC_MAINNET = 56;

    /// @dev Minimum delay between beginning and accepting a transfer of
    ///      DEFAULT_ADMIN_ROLE. It does not delay ordinary onlyRole(admin)
    ///      calls; production runtime delay belongs in the admin Safe policy.
    uint48 internal constant MIN_ADMIN_DELAY = 10 minutes;
    /// @dev TWAP window floor. A shorter window is cheaper to manipulate: an
    ///      attacker must re-skew the pool every block for the whole window, so
    ///      halving it roughly halves the attack cost. Lowered from 2h to 1h as
    ///      a deliberate, priced decision (1h ~= 2x cheaper to attack than 2h,
    ///      still 2x dearer than 30m) in exchange for fresher pricing. Do not
    ///      lower it further without re-checking pool depth: at ~$127k TVL a
    ///      10% skew already costs only ~$6.4k of capital at risk.
    uint256 internal constant MIN_TWAP_PERIOD = 1 hours;

    /// @dev Ceiling on how stale a Chainlink BNB/USD round may be before the
    ///      oracle refuses it. The feed updates roughly every 23 seconds, so a
    ///      one hour tolerance is already ~150x slack and exists only to ride
    ///      out a genuine feed outage, not to make room for a lazy keeper.
    uint256 internal constant MAX_BNB_FEED_AGE = 1 hours;

    /// @dev Source-controlled so changing an environment variable cannot create
    ///      another plausible deployment. Bump the version only through review.
    bytes32 internal constant DEPLOY_SALT = keccak256("BinaryMembershipV3:BSC_MAINNET:RWAAN:V3");

    /// @dev Commits every privileged/economic address, including the operator
    ///      and pauser that are granted only after deployment. The CREATE2
    ///      address alone cannot commit those two post-construction roles.
    bytes32 internal constant ROLE_MANIFEST_DOMAIN = keccak256("BinaryMembershipV3:BSC_MAINNET:ROLE_MANIFEST:V3");

    function run() external returns (BinaryMembershipV3 membership) {
        require(block.chainid == BSC_MAINNET, "not BSC mainnet (expected chain 56)");

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        DeploymentInputs memory inputs = _readDeploymentInputs();
        address expected = vm.envAddress("EXPECTED_MEMBERSHIP_ADDRESS");
        bytes32 expectedRoleManifest = vm.envBytes32("EXPECTED_ROLE_MANIFEST_HASH");

        // Policy is read here; the validator below is pure logic. Keeping the
        // env lookup out of the guard makes every branch testable without
        // depending on process environment state.
        bool allowEoaRoles = vm.envOr("ALLOW_EOA_ROLES", false);
        bool allowSharedControl = vm.envOr("ALLOW_SHARED_CONTROL_ADDRESS", false);
        require(deployer == vm.envAddress("DEPLOYER_ADDRESS"), "deployer key/address mismatch");
        _checkRoles(
            inputs.admin,
            inputs.operator,
            inputs.treasury,
            inputs.pauser,
            inputs.root,
            allowEoaRoles,
            allowSharedControl
        );
        _checkCompanyWallet(inputs.company, inputs.treasury, inputs.root);
        _checkDeployer(
            deployer, inputs.admin, inputs.operator, inputs.treasury, inputs.pauser, inputs.root, allowSharedControl
        );
        bytes32 roleManifest = _roleManifestHash(
            inputs.admin,
            inputs.operator,
            inputs.treasury,
            inputs.company,
            inputs.pauser,
            inputs.root,
            inputs.adminDelay
        );
        _checkRoleManifest(roleManifest, expectedRoleManifest);
        IERC20Metadata token = _checkToken();
        uint256 maxPriceAge = vm.envUint("MAX_PRICE_AGE_SECONDS");
        require(maxPriceAge > 0, "max price age is zero");
        IAssetUsdPriceOracle oracle = _checkOracle(maxPriceAge);

        // Precompute so the address can be published and cross-checked before
        // a single wei is spent, and so a retry is provably idempotent.
        address predicted = _predictAddress(address(token), address(oracle), maxPriceAge, inputs);
        _checkExpectedAddress(predicted, expected);
        require(predicted.code.length == 0, "canonical address already has code");
        console2.log("predicted address ", predicted);

        membership = _deploy(deployerKey, token, oracle, maxPriceAge, inputs);
        require(address(membership) == predicted, "CREATE2 address mismatch");

        _logDeployment(membership, token, oracle, inputs, roleManifest);
    }

    function _deploy(
        uint256 deployerKey,
        IERC20Metadata token,
        IAssetUsdPriceOracle oracle,
        uint256 maxPriceAge,
        DeploymentInputs memory inputs
    ) internal returns (BinaryMembershipV3 membership) {
        vm.startBroadcast(deployerKey);
        membership = new BinaryMembershipV3{salt: DEPLOY_SALT}(
            token, oracle, maxPriceAge, inputs.treasury, inputs.company, inputs.admin, inputs.adminDelay, inputs.root
        );
        vm.stopBroadcast();
    }

    /// @notice Read and validate the constructor inputs and print the canonical
    ///         address without reading a deployer key or broadcasting. Run this
    ///         first, independently record both printed values, then set them
    ///         as EXPECTED_MEMBERSHIP_ADDRESS and EXPECTED_ROLE_MANIFEST_HASH.
    function predictFromEnv() external view returns (address predicted) {
        require(block.chainid == BSC_MAINNET, "not BSC mainnet (expected chain 56)");

        DeploymentInputs memory inputs = _readDeploymentInputs();
        bool allowEoaRoles = vm.envOr("ALLOW_EOA_ROLES", false);
        bool allowSharedControl = vm.envOr("ALLOW_SHARED_CONTROL_ADDRESS", false);
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");

        _checkRoles(
            inputs.admin,
            inputs.operator,
            inputs.treasury,
            inputs.pauser,
            inputs.root,
            allowEoaRoles,
            allowSharedControl
        );
        _checkCompanyWallet(inputs.company, inputs.treasury, inputs.root);
        _checkDeployer(
            deployer, inputs.admin, inputs.operator, inputs.treasury, inputs.pauser, inputs.root, allowSharedControl
        );
        IERC20Metadata token = _checkToken();
        uint256 maxPriceAge = vm.envUint("MAX_PRICE_AGE_SECONDS");
        require(maxPriceAge > 0, "max price age is zero");
        IAssetUsdPriceOracle oracle = _checkOracle(maxPriceAge);
        predicted = _predictAddress(address(token), address(oracle), maxPriceAge, inputs);
        bytes32 roleManifest = _roleManifestHash(
            inputs.admin,
            inputs.operator,
            inputs.treasury,
            inputs.company,
            inputs.pauser,
            inputs.root,
            inputs.adminDelay
        );

        console2.log("canonical predicted address", predicted);
        console2.log("CREATE2 salt");
        console2.logBytes32(DEPLOY_SALT);
        console2.log("role manifest hash");
        console2.logBytes32(roleManifest);
    }

    /// @dev Roles are distinct by default. The explicit shared-control policy
    ///      accepts only admin == operator == pauser, while treasury and root
    ///      stay independent. `OPERATOR_ROLE` can enrol members into higher
    ///      stages fee-free, so enabling this deliberately concentrates power.
    function _checkRoles(
        address admin,
        address operator,
        address treasury,
        address pauser,
        address root,
        bool allowEoaRoles,
        bool allowSharedControl
    ) internal view {
        require(admin != address(0), "admin is zero");
        require(operator != address(0), "operator is zero");
        require(treasury != address(0), "treasury is zero");
        require(pauser != address(0), "pauser is zero");
        require(root != address(0), "root is zero");

        require(admin != treasury, "admin and treasury must differ");
        require(operator != treasury, "operator and treasury must differ");
        require(treasury != pauser, "treasury and pauser must differ");

        if (allowSharedControl) {
            require(admin == operator && admin == pauser, "shared control requires admin=operator=pauser");
        } else {
            require(admin != operator, "admin and operator must differ");
            require(admin != pauser, "admin and pauser must differ");
            require(operator != pauser, "operator and pauser must differ");
        }

        // The designated root is the principal economic beneficiary. It must
        // not also control fee-free stage seeding or another privileged role.
        require(root != admin, "root and admin must differ");
        require(root != operator, "root and operator must differ");
        require(root != treasury, "root and treasury must differ");
        require(root != pauser, "root and pauser must differ");

        // Opt-out exists for hardware-wallet EOAs, which have no code but are
        // still a reasonable custody choice. It must be set deliberately.
        if (!allowEoaRoles) {
            _checkSafeLike(admin, "admin");
            _checkSafeLike(operator, "operator");
            _checkSafeLike(treasury, "treasury");
            _checkSafeLike(pauser, "pauser");
        }
    }

    function _checkSafeLike(address account, string memory label) internal view {
        require(account.code.length > 0, string.concat(label, " is an EOA - use a multisig or set ALLOW_EOA_ROLES"));

        address[] memory owners;
        uint256 threshold;
        try ISafeLike(account).getOwners() returns (address[] memory configuredOwners) {
            owners = configuredOwners;
        } catch {
            revert(string.concat(label, " is not a Safe-like multisig"));
        }
        try ISafeLike(account).getThreshold() returns (uint256 configuredThreshold) {
            threshold = configuredThreshold;
        } catch {
            revert(string.concat(label, " is not a Safe-like multisig"));
        }

        require(owners.length >= 2, string.concat(label, " multisig needs at least two owners"));
        require(threshold >= 2, string.concat(label, " multisig threshold must be at least two"));
        require(threshold <= owners.length, string.concat(label, " multisig threshold exceeds owners"));
    }

    function _checkCompanyWallet(address company, address treasury, address root) internal pure {
        require(company != address(0), "company wallet is zero");
        require(company != treasury, "company and treasury must differ");
        require(company != root, "company and root must differ");
    }

    function _checkDeployer(
        address deployer,
        address admin,
        address operator,
        address treasury,
        address pauser,
        address root,
        bool allowSharedControl
    ) internal pure {
        require(deployer != address(0), "deployer is zero");
        require(deployer != treasury, "deployer and treasury must differ");
        require(deployer != root, "deployer and root must differ");

        if (allowSharedControl) {
            require(deployer == admin, "deployer must equal shared control address");
            require(deployer == operator, "deployer and operator mismatch");
            require(deployer == pauser, "deployer and pauser mismatch");
        } else {
            require(deployer != admin, "deployer and admin must differ");
            require(deployer != operator, "deployer and operator must differ");
            require(deployer != pauser, "deployer and pauser must differ");
        }
    }

    function _checkExpectedAddress(address predicted, address expected) internal pure {
        require(expected != address(0), "expected membership address is zero");
        require(predicted == expected, "predicted address does not match expected address");
    }

    function _checkRoleManifest(bytes32 actual, bytes32 expected) internal pure {
        require(expected != bytes32(0), "expected role manifest is zero");
        require(actual == expected, "role manifest does not match expected hash");
    }

    function _readDeploymentInputs() internal view returns (DeploymentInputs memory inputs) {
        inputs.admin = vm.envAddress("ADMIN_ADDRESS");
        inputs.operator = vm.envAddress("OPERATOR_ADDRESS");
        inputs.treasury = vm.envAddress("TREASURY_ADDRESS");
        inputs.company = vm.envAddress("COMPANY_WALLET_ADDRESS");
        inputs.pauser = vm.envAddress("PAUSER_ADDRESS");
        inputs.root = vm.envAddress("ROOT_ADDRESS");
        inputs.adminDelay = _checkedAdminDelay(vm.envUint("ADMIN_DELAY_SECONDS"));
    }

    function _logDeployment(
        BinaryMembershipV3 membership,
        IERC20Metadata token,
        IAssetUsdPriceOracle oracle,
        DeploymentInputs memory inputs,
        bytes32 roleManifest
    ) internal view {
        console2.log("");
        console2.log("=== DEPLOYED ===");
        console2.log("membership        ", address(membership));
        console2.log("payment token     ", address(token));
        console2.log("token decimals    ", token.decimals());
        console2.log("USD price oracle  ", address(oracle));
        console2.log("max price age (s) ", membership.maxPriceAge());
        console2.log("admin             ", inputs.admin);
        console2.log("admin delay (s)   ", inputs.adminDelay);
        console2.log("designated root   ", inputs.root);
        console2.log("treasury          ", inputs.treasury);
        console2.log("company wallet    ", inputs.company);
        console2.log("CREATE2 salt      ");
        console2.logBytes32(DEPLOY_SALT);
        console2.log("role manifest     ");
        console2.logBytes32(roleManifest);
        console2.log("");
        console2.log("NOT YET CONFIGURED. Roles, stages and the cycle guard are");
        console2.log("set by the admin role holder - see the production runbook.");
        console2.log("The contract cannot take a member until that is done.");
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

    function _predictAddress(address token, address oracle, uint256 maxPriceAge, DeploymentInputs memory inputs)
        internal
        pure
        returns (address)
    {
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(BinaryMembershipV3).creationCode,
                abi.encode(
                    IERC20Metadata(token),
                    IAssetUsdPriceOracle(oracle),
                    maxPriceAge,
                    inputs.treasury,
                    inputs.company,
                    inputs.admin,
                    inputs.adminDelay,
                    inputs.root
                )
            )
        );
        return vm.computeCreate2Address(DEPLOY_SALT, initCodeHash);
    }

    function deploymentSalt() external pure returns (bytes32) {
        return DEPLOY_SALT;
    }

    function _checkedAdminDelay(uint256 rawDelay) internal pure returns (uint48 adminDelay) {
        require(rawDelay <= type(uint48).max, "admin delay exceeds uint48");
        adminDelay = uint48(rawDelay);
        _checkAdminDelay(adminDelay);
    }

    function _checkAdminDelay(uint48 adminDelay) internal pure {
        require(adminDelay != 0, "admin delay must not be zero on mainnet");
        require(adminDelay >= MIN_ADMIN_DELAY, "admin delay below the safe floor");
    }

    /// @dev The address is the identity. Symbol and decimals are corroboration
    ///      only — a malicious contract can report anything, so a check that
    ///      passes on name alone would be worthless.
    function _checkToken() internal view returns (IERC20Metadata token) {
        token = IERC20Metadata(BSC_RWAAN);

        require(BSC_RWAAN.code.length > 0, "payment token has no code");
        require(token.decimals() == 18, "payment token must have 18 decimals");
        require(token.totalSupply() > 0, "payment token has no supply");
    }

    function _checkOracle(uint256 maxPriceAge) internal view returns (IAssetUsdPriceOracle oracle) {
        address oracleAddress = vm.envAddress("PRICE_ORACLE_ADDRESS");
        require(oracleAddress == vm.envAddress("EXPECTED_PRICE_ORACLE_ADDRESS"), "unexpected price oracle");
        require(oracleAddress.code.length > 0, "price oracle has no code");
        PancakeV2RwaanUsdOracle productionOracle = PancakeV2RwaanUsdOracle(oracleAddress);
        require(productionOracle.rwaan() == BSC_RWAAN, "oracle has wrong RWAAN");
        require(productionOracle.wrappedBnb() == WBNB, "oracle has wrong WBNB");
        require(address(productionOracle.pair()) == RWAAN_WBNB_PAIR, "oracle has wrong pair");
        require(address(productionOracle.bnbUsdFeed()) == BNB_USD_FEED, "oracle has wrong BNB/USD feed");
        require(productionOracle.period() == vm.envUint("TWAP_PERIOD_SECONDS"), "oracle has wrong period");
        require(productionOracle.period() >= MIN_TWAP_PERIOD, "TWAP period below production floor");
        require(productionOracle.bnbFeedMaxAge() == vm.envUint("BNB_FEED_MAX_AGE_SECONDS"), "oracle has wrong feed age");

        // The two staleness budgets are independent and must not be coupled.
        //
        // `latestPriceUsd` returns `min(twapUpdatedAt, feedUpdatedAt)`, and the
        // BNB/USD feed refreshes every ~23s, so in practice that minimum is
        // always the TWAP timestamp. `maxPriceAge` is therefore a TWAP
        // staleness budget, while the feed's own freshness is enforced inside
        // the oracle, which reverts `StaleBnbPrice` before returning anything.
        //
        // The previous guard required `maxPriceAge <= bnbFeedMaxAge`, which
        // forced the Chainlink tolerance to be widened just to buy keeper
        // headroom on the TWAP. That traded away real protection for an
        // operational convenience. The feed tolerance is now capped on its own
        // terms instead.
        require(
            productionOracle.bnbFeedMaxAge() <= MAX_BNB_FEED_AGE,
            "BNB feed tolerance too loose"
        );
        require(maxPriceAge >= productionOracle.period(), "membership price age below TWAP period");
        oracle = IAssetUsdPriceOracle(oracleAddress);

        (uint256 priceUsd18, uint256 updatedAt) = oracle.latestPriceUsd();
        require(priceUsd18 > 0, "oracle price is zero");
        require(updatedAt > 0 && updatedAt <= block.timestamp, "invalid oracle timestamp");
        require(block.timestamp - updatedAt <= maxPriceAge, "oracle price is stale");
    }
}
