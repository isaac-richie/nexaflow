// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {
    PancakeV2RwaanUsdOracle,
    IPancakeV2Pair,
    IAggregatorV3
} from "../src/PancakeV2RwaanUsdOracle.sol";

/// @notice Deploy, initialize and verify the production RWAAN/USD oracle.
contract DeployRwaanOracle is Script {
    uint256 internal constant BSC_MAINNET = 56;
    address internal constant RWAAN = 0xACB921bf2Dac2F7E8E101AAd9CA013d6Af5C648a;
    address internal constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address internal constant RWAAN_WBNB_PAIR = 0xA285059BBc89Fe9B43414D098318675462aaa3e6;
    address internal constant BNB_USD_FEED = 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE;
    /// @dev See DeployBscMainnet.MIN_TWAP_PERIOD for the reasoning behind the
    ///      1 hour floor. Keep the two in sync.
    uint256 internal constant MIN_TWAP_PERIOD = 1 hours;
    uint256 internal constant MAX_BNB_FEED_AGE = 1 hours;
    bytes32 internal constant DEPLOY_SALT = keccak256("RWAAN_USD_ORACLE:BSC_MAINNET:V1");

    function run() external returns (PancakeV2RwaanUsdOracle oracle) {
        require(block.chainid == BSC_MAINNET, "not BSC mainnet (expected chain 56)");
        uint256 period = vm.envUint("TWAP_PERIOD_SECONDS");
        uint256 feedMaxAge = vm.envUint("BNB_FEED_MAX_AGE_SECONDS");
        _checkTiming(period, feedMaxAge);
        address expected = vm.envAddress("EXPECTED_PRICE_ORACLE_ADDRESS");
        address predicted = _predictAddress(period, feedMaxAge);
        require(expected != address(0) && predicted == expected, "unexpected oracle address");
        require(predicted.code.length == 0, "oracle already deployed");

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        require(vm.addr(deployerKey) == vm.envAddress("DEPLOYER_ADDRESS"), "deployer key/address mismatch");

        vm.startBroadcast(deployerKey);
        oracle = new PancakeV2RwaanUsdOracle{salt: DEPLOY_SALT}(
            RWAAN,
            WBNB,
            IPancakeV2Pair(RWAAN_WBNB_PAIR),
            IAggregatorV3(BNB_USD_FEED),
            period,
            feedMaxAge
        );
        vm.stopBroadcast();

        require(address(oracle) == predicted, "CREATE2 oracle address mismatch");
        console2.log("RWAAN/USD oracle  ", address(oracle));
        console2.log("TWAP period (s)   ", period);
        console2.log("Wait one full TWAP period, then call updateFromEnv().");
    }

    function predictFromEnv() external view returns (address predicted) {
        require(block.chainid == BSC_MAINNET, "not BSC mainnet (expected chain 56)");
        uint256 period = vm.envUint("TWAP_PERIOD_SECONDS");
        uint256 feedMaxAge = vm.envUint("BNB_FEED_MAX_AGE_SECONDS");
        _checkTiming(period, feedMaxAge);
        predicted = _predictAddress(period, feedMaxAge);
        console2.log("canonical predicted oracle", predicted);
        console2.logBytes32(DEPLOY_SALT);
    }

    function updateFromEnv() external {
        require(block.chainid == BSC_MAINNET, "not BSC mainnet (expected chain 56)");
        PancakeV2RwaanUsdOracle oracle =
            PancakeV2RwaanUsdOracle(vm.envAddress("PRICE_ORACLE_ADDRESS"));
        uint256 updaterKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(updaterKey);
        oracle.update();
        vm.stopBroadcast();

        (uint256 priceUsd18, uint256 updatedAt) = oracle.latestPriceUsd();
        console2.log("RWAAN price USD 18", priceUsd18);
        console2.log("oracle updated at ", updatedAt);
    }

    function verifyFromEnv() external view returns (bool) {
        require(block.chainid == BSC_MAINNET, "not BSC mainnet (expected chain 56)");
        require(
            vm.envAddress("PRICE_ORACLE_ADDRESS") == vm.envAddress("EXPECTED_PRICE_ORACLE_ADDRESS"),
            "unexpected oracle address"
        );
        PancakeV2RwaanUsdOracle oracle =
            PancakeV2RwaanUsdOracle(vm.envAddress("PRICE_ORACLE_ADDRESS"));
        require(oracle.rwaan() == RWAAN, "wrong RWAAN");
        require(oracle.wrappedBnb() == WBNB, "wrong WBNB");
        require(address(oracle.pair()) == RWAAN_WBNB_PAIR, "wrong pair");
        require(address(oracle.bnbUsdFeed()) == BNB_USD_FEED, "wrong BNB/USD feed");
        require(oracle.period() == vm.envUint("TWAP_PERIOD_SECONDS"), "wrong TWAP period");
        require(oracle.bnbFeedMaxAge() == vm.envUint("BNB_FEED_MAX_AGE_SECONDS"), "wrong feed age");
        _checkTiming(oracle.period(), oracle.bnbFeedMaxAge());
        (uint256 priceUsd18,) = oracle.latestPriceUsd();
        require(priceUsd18 > 0, "oracle not ready");
        return true;
    }

    function _predictAddress(uint256 period, uint256 feedMaxAge) internal pure returns (address) {
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(PancakeV2RwaanUsdOracle).creationCode,
                abi.encode(
                    RWAAN,
                    WBNB,
                    IPancakeV2Pair(RWAAN_WBNB_PAIR),
                    IAggregatorV3(BNB_USD_FEED),
                    period,
                    feedMaxAge
                )
            )
        );
        return vm.computeCreate2Address(DEPLOY_SALT, initCodeHash);
    }

    function _checkTiming(uint256 period, uint256 feedMaxAge) internal pure {
        require(period >= MIN_TWAP_PERIOD, "TWAP period below production floor");
        // Capped on its own terms: the BNB/USD feed updates every ~23s, so a
        // wide tolerance here protects nobody and hides a real outage.
        require(feedMaxAge <= MAX_BNB_FEED_AGE, "BNB feed tolerance too loose");
    }
}
