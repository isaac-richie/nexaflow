// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {console2} from "forge-std/console2.sol";

import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";

/// @dev Creates a local account before its runtime is replaced with the exact
///      canonical token runtime supplied by the release command.
contract ForkTokenShell {}

contract ForkActor {}

/// @title Read-only BSC mainnet token-runtime launch rehearsal
/// @notice LEGACY V1 ONLY. Uses the retired Binance-Peg USDT runtime and 140 synthetic
///         members across all six stages. The runner fetches the bytecode from
///         BSC immediately before execution; this script rejects any code-hash
///         drift. There is no broadcast call and no private key input.
contract AuditBscMainnetRuntime is Test {
    address internal constant BSC_USDT = 0x55d398326f99059fF775485246999027B3197955;
    bytes32 internal constant EXPECTED_USDT_RUNTIME_HASH =
        0x97a48aa4c129657440dafdacd4c836389734d28cc4a0ca7403e68da660a74a59;

    uint256 internal constant UNIT = 1e18;
    uint256 internal constant WALLET_COUNT = 140;

    address internal admin;
    address internal root;
    address internal operator;
    address internal treasury;
    address internal pauser;
    IERC20Metadata internal token;
    BinaryMembershipV1 internal membership;
    address[] internal members;

    uint256[6] internal fees = [uint256(20 * UNIT), 60 * UNIT, 180 * UNIT, 540 * UNIT, 1_620 * UNIT, 4_860 * UNIT];

    function run() external {
        bytes memory liveRuntime = vm.envBytes("BSC_USDT_RUNTIME");
        assertGt(liveRuntime.length, 0, "BSC USDT runtime is empty");
        assertEq(keccak256(liveRuntime), EXPECTED_USDT_RUNTIME_HASH, "BSC USDT runtime hash changed");

        // Copying the canonical runtime into a new local account preserves the
        // exact approve/transferFrom implementation while all synthetic token
        // balances remain local and deterministic.
        ForkTokenShell shell = new ForkTokenShell();
        vm.etch(address(shell), liveRuntime);
        assertEq(keccak256(address(shell).code), EXPECTED_USDT_RUNTIME_HASH, "live token runtime copy failed");
        vm.store(address(shell), bytes32(uint256(3)), bytes32(uint256(2_000_000 * UNIT)));
        vm.store(address(shell), bytes32(uint256(4)), bytes32(uint256(18)));
        vm.store(address(shell), bytes32(uint256(5)), bytes32("USDT") | bytes32(uint256(8)));
        vm.store(address(shell), bytes32(uint256(6)), bytes32("Tether USD") | bytes32(uint256(20)));
        token = IERC20Metadata(address(shell));
        assertEq(token.decimals(), 18, "local runtime decimals initialization failed");
        assertEq(token.symbol(), "USDT", "local runtime symbol initialization failed");

        admin = address(new ForkActor());
        root = address(new ForkActor());
        operator = address(new ForkActor());
        treasury = address(new ForkActor());
        pauser = address(new ForkActor());

        membership = new BinaryMembershipV1(IERC20(address(token)), treasury, admin, uint48(10 minutes), root);
        vm.startPrank(admin);
        membership.grantRole(membership.OPERATOR_ROLE(), operator);
        membership.grantRole(membership.TREASURY_ROLE(), treasury);
        membership.grantRole(membership.PAUSER_ROLE(), pauser);
        membership.configureStages(
            fees,
            [uint256(5 * UNIT), 10 * UNIT, 25 * UNIT, 80 * UNIT, 250 * UNIT, 800 * UNIT],
            [uint256(6), 14, 14, 14, 14, 14],
            [uint256(2), 3, 3, 3, 3, 3],
            [uint256(0), 10, 10, 10, 10, 8]
        );
        membership.setCycleGuardEnabled(true);
        vm.stopPrank();

        vm.prank(root);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);
        for (uint256 stageId = 1; stageId < 6; stageId++) {
            vm.prank(operator);
            membership.enrollStageRoot(root, stageId);
        }

        _fundAndApproveMembers();
        _runAllStages();
        _assertFinalAccounting();

        console2.log("canonical live token", BSC_USDT);
        console2.log("reviewed runtime hash");
        console2.logBytes32(EXPECTED_USDT_RUNTIME_HASH);
        console2.log("local exact-runtime token", address(token));
        console2.log("local membership", address(membership));
        console2.log("members across all stages", WALLET_COUNT);
        console2.log("total fees", membership.totalPoolPaid() + membership.totalTreasuryPaid());
        console2.log("total node rewards", membership.totalPoolPaid());
        console2.log("pending treasury", membership.pendingTreasury());
        console2.log("physical awards paid", membership.totalAwardsPaid());
        console2.log("MAINNET TOKEN-RUNTIME REHEARSAL: PASS");
    }

    function _fundAndApproveMembers() internal {
        for (uint256 i; i < WALLET_COUNT; i++) {
            address member = address(new ForkActor());
            members.push(member);

            // The verified BSC-USDT bytecode stores balances in mapping slot 1.
            // Writing this exact key avoids StdCheats' broad slot-probing,
            // which pruned public BSC RPCs cannot answer. This changes only
            // local storage; approve/transferFrom still execute the canonical
            // token bytecode. The assertion fails if that layout ever changes.
            bytes32 balanceSlot = keccak256(abi.encode(member, uint256(1)));
            vm.store(address(token), balanceSlot, bytes32(uint256(10_000 * UNIT)));
            assertEq(token.balanceOf(member), 10_000 * UNIT, "local USDT funding failed");
            vm.prank(member);
            token.approve(address(membership), type(uint256).max);
        }
    }

    function _runAllStages() internal {
        for (uint256 i; i < WALLET_COUNT; i++) {
            address sponsor = i < 10 ? root : members[(i - 10) / 2];
            (address parent, BinaryMembershipV1.Side side) = membership.findPlacementSlot(sponsor, 0);
            vm.prank(members[i]);
            membership.register(sponsor, parent, side);
        }

        for (uint256 stageId = 1; stageId < 6; stageId++) {
            for (uint256 i; i < WALLET_COUNT; i++) {
                (address parent, BinaryMembershipV1.Side side) = membership.findOpenSlot(root, stageId);
                vm.prank(members[i]);
                membership.joinStage(stageId, parent, side);
            }

            (,,, uint256 nextMilestone, bool eligible) = membership.getAwardInfo(root, stageId);
            assertTrue(eligible, "root did not reach physical-award milestone");
            assertEq(nextMilestone, stageId == 5 ? 8 : 10, "wrong physical-award milestone");
            vm.prank(operator);
            membership.grantPhysicalAward(root, stageId, UNIT);
        }
    }

    function _assertFinalAccounting() internal view {
        uint256 expectedFees;
        for (uint256 stageId; stageId < 6; stageId++) {
            expectedFees += WALLET_COUNT * fees[stageId];
        }

        assertEq(membership.memberCount(), WALLET_COUNT + 1, "member count mismatch");
        assertEq(membership.totalPoolPaid() + membership.totalTreasuryPaid(), expectedFees, "fee conservation mismatch");
        assertEq(token.balanceOf(address(membership)), membership.pendingTreasury(), "treasury is insolvent");
        assertEq(membership.totalAwardsPaid(), 5 * UNIT, "physical-award total mismatch");

        for (uint256 stageId = 1; stageId < 5; stageId++) {
            (,,, uint256 nextMilestone, bool eligible) = membership.getAwardInfo(root, stageId);
            assertEq(nextMilestone, 20, "ten-rollover award did not advance");
            assertFalse(eligible, "repeat award unlocked early");
        }
        (,,, uint256 finalMilestone, bool finalEligible) = membership.getAwardInfo(root, 5);
        assertEq(finalMilestone, 16, "eight-rollover final award did not advance");
        assertFalse(finalEligible, "repeat final-stage award unlocked early");
    }
}
