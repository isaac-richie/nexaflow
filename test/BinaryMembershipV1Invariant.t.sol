// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BinaryMembershipHandler is Test {
    BinaryMembershipV1 public membership;
    MockERC20 public token;

    address public admin;
    address public treasury;
    address public operator;
    address public pauser;
    address public root;

    address[] public actors;
    uint256 public nextActorIdx;

    // Ghost variables for conservation tracking
    uint256 public ghostTotalFeesPulled;
    uint256 public ghostTotalTreasuryWithdrawn;
    uint256 public ghostTotalAwardsPaid;

    // Track registered actors for stage operations
    address[] public registeredActors;

    constructor(
        BinaryMembershipV1 _membership,
        MockERC20 _token,
        address _admin,
        address _treasury,
        address _operator,
        address _pauser,
        address _root
    ) {
        membership = _membership;
        token = _token;
        admin = _admin;
        treasury = _treasury;
        operator = _operator;
        pauser = _pauser;
        root = _root;

        // Pre-create 100 actor addresses
        for (uint256 i = 0; i < 100; i++) {
            address actor = address(uint160(0x10000 + i));
            actors.push(actor);
            token.mint(actor, 1_000_000 ether);
            vm.prank(actor);
            token.approve(address(membership), type(uint256).max);
        }
    }

    function _nextActor() internal returns (address) {
        if (nextActorIdx >= actors.length) return address(0);
        return actors[nextActorIdx++];
    }

    // ── Action: register ─────────────────────────────────────────────

    function handler_register(uint256 sponsorSeed, uint256 sideSeed) external {
        address actor = _nextActor();
        if (actor == address(0)) return;
        if (membership.getMember(actor).active) return;

        // Pick a random sponsor from registered actors (or root)
        address sponsor;
        if (registeredActors.length == 0) {
            sponsor = root;
        } else {
            sponsor = registeredActors[sponsorSeed % registeredActors.length];
        }

        // Find open slot via BFS from sponsor (or root)
        address searchRoot = sponsor;
        try membership.findOpenSlot(searchRoot, 0) returns (
            address parent, BinaryMembershipV1.Side side
        ) {
            if (parent == address(0)) {
                // Try from root instead
                try membership.findOpenSlot(root, 0) returns (
                    address p2, BinaryMembershipV1.Side s2
                ) {
                    if (p2 == address(0)) return;
                    parent = p2;
                    side = s2;
                } catch {
                    return;
                }
            }

            vm.prank(actor);
            try membership.register(sponsor, parent, side) {
                ghostTotalFeesPulled += 20 ether; // FEE_1
                registeredActors.push(actor);
            } catch {}
        } catch {
            return;
        }
    }

    // ── Action: joinStage ────────────────────────────────────────────

    function handler_joinStage(uint256 actorSeed, uint256 stageIdRaw) external {
        if (registeredActors.length == 0) return;

        address actor = registeredActors[actorSeed % registeredActors.length];
        uint256 stageId = bound(stageIdRaw, 1, 5);

        BinaryMembershipV1.StageMembership memory prevStage =
            membership.getStageMembership(actor, stageId - 1);
        if (!prevStage.enrolled) return;

        BinaryMembershipV1.StageMembership memory thisStage =
            membership.getStageMembership(actor, stageId);
        if (thisStage.enrolled) return;

        // Need a root at this stage first
        try membership.findOpenSlot(root, stageId) returns (
            address parent, BinaryMembershipV1.Side side
        ) {
            if (parent == address(0)) return;

            BinaryMembershipV1.StageConfig memory config = membership.getStageConfig(stageId);

            vm.prank(actor);
            try membership.joinStage(stageId, parent, side) {
                ghostTotalFeesPulled += config.fee;
            } catch {}
        } catch {
            return;
        }
    }

    // ── Action: withdrawTreasury ─────────────────────────────────────

    function handler_withdrawTreasury(uint256 amountSeed) external {
        uint256 pending = membership.pendingTreasury();
        if (pending == 0) return;

        uint256 amount = bound(amountSeed, 1, pending);

        vm.prank(treasury);
        try membership.withdrawTreasury(amount) {
            ghostTotalTreasuryWithdrawn += amount;
        } catch {}
    }

    // ── Action: grantPhysicalAward ───────────────────────────────────

    function handler_grantAward(uint256 actorSeed, uint256 stageIdRaw, uint256 amount) external {
        if (registeredActors.length == 0) return;

        address actor = registeredActors[actorSeed % registeredActors.length];
        uint256 stageId = bound(stageIdRaw, 0, 5);
        amount = bound(amount, 0, 1000 ether);

        vm.prank(operator);
        try membership.grantPhysicalAward(actor, stageId, amount) {
            ghostTotalAwardsPaid += amount;
        } catch {}
    }

    // ── Action: pause/unpause ────────────────────────────────────────

    function handler_togglePause() external {
        vm.startPrank(pauser);
        if (membership.paused()) {
            membership.unpause();
        } else {
            membership.pause();
            membership.unpause(); // immediately unpause to not block other actions
        }
        vm.stopPrank();
    }

    // ── Action: enrollStageRoot ──────────────────────────────────────

    function handler_enrollStageRoot(uint256 stageIdRaw) external {
        uint256 stageId = bound(stageIdRaw, 1, 5);

        BinaryMembershipV1.StageMembership memory prevStage =
            membership.getStageMembership(root, stageId - 1);
        if (!prevStage.enrolled) return;

        BinaryMembershipV1.StageMembership memory thisStage =
            membership.getStageMembership(root, stageId);
        if (thisStage.enrolled) return;

        vm.prank(operator);
        try membership.enrollStageRoot(root, stageId) {} catch {}
    }

    // ── Action: time warp ────────────────────────────────────────────

    function handler_warp(uint256 seconds_) external {
        seconds_ = bound(seconds_, 1, 7 days);
        vm.warp(block.timestamp + seconds_);
    }

    // ── Views for invariant assertions ───────────────────────────────

    function registeredActorsLength() external view returns (uint256) {
        return registeredActors.length;
    }
}

contract BinaryMembershipV1InvariantTest is Test {
    BinaryMembershipV1 public membership;
    MockERC20 public token;
    BinaryMembershipHandler public handler;

    address admin = address(0xAD);
    address treasury = address(0x7777);
    address operator = address(0x8888);
    address pauser = address(0x9999);
    address root = address(0x1);

    uint256 constant INITIAL_FUNDING = 10_000_000 ether;

    function setUp() public {
        token = new MockERC20("FAKEUSD", "FUSD", 18);

        vm.startPrank(admin);
        membership = new BinaryMembershipV1(
            IERC20(address(token)), treasury, admin, 0, root
        );
        membership.grantRole(membership.OPERATOR_ROLE(), operator);
        membership.grantRole(membership.TREASURY_ROLE(), treasury);
        membership.grantRole(membership.PAUSER_ROLE(), pauser);

        membership.configureStages(
            [uint256(20 ether), 60 ether, 180 ether, 540 ether, 1620 ether, 4860 ether],
            [uint256(5 ether), 10 ether, 25 ether, 80 ether, 250 ether, 800 ether],
            [uint256(6), 14, 14, 14, 14, 14],
            [uint256(2), 3, 3, 3, 3, 3],
            [uint256(0), 10, 10, 10, 10, 8]
        );
        vm.stopPrank();

        // Register root
        vm.prank(root);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);

        // Fund contract for reward payouts
        token.mint(address(membership), INITIAL_FUNDING);

        handler = new BinaryMembershipHandler(
            membership, token, admin, treasury, operator, pauser, root
        );

        targetContract(address(handler));
    }

    // ── Invariant 1: Solvency ────────────────────────────────────────

    function invariant_Solvency() public view {
        assertGe(
            token.balanceOf(address(membership)),
            membership.pendingTreasury(),
            "INSOLVENT: contract balance < pendingTreasury"
        );
    }

    // ── Invariant 2: Fee conservation ────────────────────────────────

    function invariant_FeeConservation() public view {
        assertEq(
            handler.ghostTotalFeesPulled(),
            membership.totalPoolPaid() + membership.totalTreasuryPaid(),
            "Fee conservation violated: feesPulled != poolPaid + treasuryPaid"
        );
    }

    // ── Invariant 3: Treasury accounting ─────────────────────────────

    function invariant_TreasuryAccounting() public view {
        assertEq(
            membership.pendingTreasury(),
            membership.totalTreasuryPaid() - handler.ghostTotalTreasuryWithdrawn(),
            "Treasury accounting mismatch"
        );
    }

    // ── Invariant 4: Member count matches registered actors ──────────

    function invariant_MemberCount() public view {
        // memberCount includes the root (+1)
        assertEq(
            membership.memberCount(),
            handler.registeredActorsLength() + 1,
            "memberCount != registered actors + root"
        );
    }

    // ── Invariant 5: Contract balance conservation ───────────────────

    function invariant_BalanceConservation() public view {
        uint256 contractBal = token.balanceOf(address(membership));
        uint256 expected = INITIAL_FUNDING
            + handler.ghostTotalFeesPulled()
            - membership.totalPoolPaid()
            - handler.ghostTotalTreasuryWithdrawn()
            - handler.ghostTotalAwardsPaid();

        assertEq(contractBal, expected, "Balance conservation violated");
    }
}
