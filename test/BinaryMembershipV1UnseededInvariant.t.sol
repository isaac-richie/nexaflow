// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Handler for the unseeded solvency campaign.
contract UnseededHandler is Test {
    BinaryMembershipV1 public membership;
    MockERC20 public token;

    address public constant ROOT = address(0x1);
    address public constant OPERATOR = address(0x0B);
    address public constant TREASURY = address(0x7EA5);

    address[] public actors;

    // Ghost totals, tracked independently of the contract.
    uint256 public gFeesPaid;      // every fee pulled from a member
    uint256 public gFunded;        // every top-up via fundTreasury
    uint256 public gWithdrawn;
    uint256 public gAwarded;

    constructor(BinaryMembershipV1 _m, MockERC20 _t) {
        membership = _m;
        token = _t;
    }

    function _actor(uint256 seed) internal returns (address a) {
        a = address(uint160(0xE00000 + (seed % 300)));
        if (token.allowance(a, address(membership)) == 0) {
            token.mint(a, 1_000_000 ether);
            vm.prank(a);
            token.approve(address(membership), type(uint256).max);
        }
    }

    /// @dev Registers a small batch. One member per call never fills a board,
    ///      so rollovers -- and therefore the award path -- stayed unreachable
    ///      and the campaign proved nothing about them.
    function handler_register(uint256 seed) external {
        uint256 fee = membership.getStageConfig(0).fee;

        for (uint256 k = 0; k < 8; k++) {
            address user = _actor(seed + k * 7919);
            if (membership.getMember(user).active) continue;

            try membership.findPlacementSlot(ROOT, 0) returns (
                address parent,
                BinaryMembershipV1.Side side
            ) {
                vm.prank(user);
                try membership.register(ROOT, parent, side) {
                    gFeesPaid += fee;
                } catch {}
            } catch {}
        }
    }

    /// @dev Same reasoning at the higher stages.
    function handler_joinStageBatch(uint256 seed, uint256 rawStage) external {
        uint256 stageId = 1 + (rawStage % 5);
        if (membership.stageAnchor(stageId) == address(0)) return;
        uint256 fee = membership.getStageConfig(stageId).fee;

        for (uint256 k = 0; k < 8; k++) {
            address user = _actor(seed + k * 104729);
            if (!membership.getMember(user).active) continue;
            if (!membership.getStageMembership(user, stageId - 1).enrolled) continue;
            if (membership.getStageMembership(user, stageId).enrolled) continue;

            try membership.findPlacementSlot(user, stageId) returns (
                address parent,
                BinaryMembershipV1.Side side
            ) {
                vm.prank(user);
                try membership.joinStage(stageId, parent, side) {
                    gFeesPaid += fee;
                } catch {}
            } catch {}
        }
    }

    function handler_joinStage(uint256 seed, uint256 rawStage) external {
        uint256 stageId = 1 + (rawStage % 5);
        address user = _actor(seed);
        if (!membership.getMember(user).active) return;
        if (!membership.getStageMembership(user, stageId - 1).enrolled) return;
        if (membership.getStageMembership(user, stageId).enrolled) return;
        if (membership.stageAnchor(stageId) == address(0)) return;

        try membership.findPlacementSlot(user, stageId) returns (
            address parent,
            BinaryMembershipV1.Side side
        ) {
            uint256 fee = membership.getStageConfig(stageId).fee;
            vm.prank(user);
            try membership.joinStage(stageId, parent, side) {
                gFeesPaid += fee;
            } catch {}
        } catch {}
    }

    function handler_enrollStageRoot(uint256 rawStage) external {
        uint256 stageId = 1 + (rawStage % 5);
        if (!membership.getStageMembership(ROOT, stageId - 1).enrolled) return;
        if (membership.getStageMembership(ROOT, stageId).enrolled) return;
        vm.prank(OPERATOR);
        try membership.enrollStageRoot(ROOT, stageId) {} catch {}
    }

    function handler_grantAward(uint256 seed, uint256 rawStage, uint256 amount) external {
        uint256 stageId = 1 + (rawStage % 5);
        address who = seed % 2 == 0 ? ROOT : _actor(seed);
        uint256 capped = amount % (500 ether + 1);

        vm.prank(OPERATOR);
        try membership.grantPhysicalAward(who, stageId, capped) {
            gAwarded += capped;
        } catch {}
    }

    function handler_withdrawTreasury(uint256 amount) external {
        uint256 pending = membership.pendingTreasury();
        if (pending == 0) return;
        uint256 take = amount % (pending + 1);

        vm.prank(TREASURY);
        try membership.withdrawTreasury(take) {
            gWithdrawn += take;
        } catch {}
    }

    function handler_fundTreasury(uint256 seed, uint256 amount) external {
        address funder = _actor(seed);
        uint256 give = 1 + (amount % 1000 ether);

        vm.prank(funder);
        try membership.fundTreasury(give) {
            gFunded += give;
        } catch {}
    }
}

/// @notice Solvency invariants against a contract that was NEVER pre-funded.
///
///  This suite exists because a generous fixture hid a real bug. Every other
///  harness mints the contract a large opening balance, which silently absorbs
///  any payment the accounting does not account for — `grantPhysicalAward` was
///  transferring tokens without reducing `pendingTreasury`, and both the
///  Foundry invariants and a 200k-call Echidna campaign passed anyway.
///
///  Here the contract's only funds are member fees and explicit `fundTreasury`
///  top-ups, so the balance is exactly what the protocol has actually taken in.
///  Any unaccounted transfer breaks `invariant_Solvent` immediately.
contract BinaryMembershipV1UnseededInvariantTest is StdInvariant, Test {
    BinaryMembershipV1 internal membership;
    MockERC20 internal token;
    UnseededHandler internal handler;

    address internal constant ADMIN = address(0xAD);
    address internal constant TREASURY = address(0x7EA5);
    address internal constant OPERATOR = address(0x0B);
    address internal constant ROOT = address(0x1);

    function setUp() public {
        token = new MockERC20("FAKEUSD", "FUSD", 0);

        vm.startPrank(ADMIN);
        membership = new BinaryMembershipV1(
            IERC20(address(token)), TREASURY, ADMIN, 0, ROOT
        );
        membership.grantRole(membership.OPERATOR_ROLE(), OPERATOR);
        membership.grantRole(membership.TREASURY_ROLE(), TREASURY);
        membership.configureStages(
            [uint256(20 ether), 60 ether, 180 ether, 540 ether, 1620 ether, 4860 ether],
            [uint256(5 ether), 10 ether, 25 ether, 80 ether, 250 ether, 800 ether],
            [uint256(6), 14, 14, 14, 14, 14],
            [uint256(2), 3, 3, 3, 3, 3],
            [uint256(0), 1, 1, 1, 1, 1] // low threshold so awards are reachable
        );
        vm.stopPrank();

        token.mint(ROOT, 1_000_000 ether);
        vm.prank(ROOT);
        token.approve(address(membership), type(uint256).max);
        vm.prank(ROOT);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);

        // NOTE: deliberately NO token.mint(address(membership), ...).

        handler = new UnseededHandler(membership, token);
        targetContract(address(handler));
    }

    /// @notice The contract can always pay what its books say it owes.
    function invariant_Solvent() public view {
        assertGe(
            token.balanceOf(address(membership)),
            membership.pendingTreasury(),
            "balance is below the recorded treasury liability"
        );
    }

    /// @notice Every token in equals every token accounted for.
    function invariant_BalanceReconciles() public view {
        uint256 inflow = handler.gFeesPaid() + handler.gFunded();
        uint256 outflow =
            membership.totalPoolPaid() + handler.gWithdrawn() + handler.gAwarded();

        assertEq(
            token.balanceOf(address(membership)),
            inflow - outflow,
            "contract balance does not reconcile with tracked flows"
        );
    }

    /// @notice Fees split exactly, with no third destination.
    function invariant_FeeConservation() public view {
        assertEq(
            membership.totalPoolPaid() + membership.totalTreasuryPaid(),
            handler.gFeesPaid() + handler.gFunded(),
            "fees are not fully split between pool and treasury"
        );
    }

    /// @notice Awards and withdrawals both draw down the same recorded pot.
    function invariant_TreasuryLedger() public view {
        assertEq(
            membership.pendingTreasury(),
            membership.totalTreasuryPaid()
                - handler.gWithdrawn()
                - membership.totalAwardsPaid(),
            "pendingTreasury drifted from its own ledger"
        );
    }
}
