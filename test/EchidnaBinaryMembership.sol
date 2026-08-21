// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract EchidnaBinaryMembership {
    BinaryMembershipV1 public membership;
    MockERC20 public token;

    address internal constant TREASURY = address(0x7777);
    address internal constant ROOT = address(0x1);

    uint256 internal constant INITIAL_FUNDING = 10_000_000 ether;
    uint256 internal constant FEE_0 = 20 ether;
    uint256 internal constant NODE_0 = 5 ether;

    // Ghost accounting
    uint256 public ghostFeesPulled;
    uint256 public ghostTreasuryWithdrawn;
    uint256 public ghostAwardsPaid;

    // Track members for targeted actions
    address[] public registeredMembers;
    uint256 public nextUserSeed;

    constructor() {
        token = new MockERC20("FAKEUSD", "FUSD", 0);

        membership = new BinaryMembershipV1(
            IERC20(address(token)), TREASURY, address(this), 0, address(this)
        );

        membership.grantRole(membership.OPERATOR_ROLE(), address(this));
        membership.grantRole(membership.TREASURY_ROLE(), address(this));
        membership.grantRole(membership.PAUSER_ROLE(), address(this));

        membership.configureStages(
            [uint256(FEE_0), 60 ether, 180 ether, 540 ether, 1620 ether, 4860 ether],
            [uint256(NODE_0), 10 ether, 25 ether, 80 ether, 250 ether, 800 ether],
            [uint256(6), 14, 14, 14, 14, 14],
            [uint256(2), 3, 3, 3, 3, 3],
            [uint256(0), 10, 10, 10, 10, 8]
        );

        // Fund contract for payouts
        token.mint(address(membership), INITIAL_FUNDING);

        // Register root (we are the deployer, so we call as ROOT via a proxy pattern)
        // Root needs to register itself — fund and approve
        token.mint(ROOT, 1_000_000 ether);
        // We can't prank in Echidna, so we make this contract the root
        // Actually — re-architecture: make this contract itself register as root
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);
    }

    // ── Helper: create and fund a unique user ────────────────────────

    function _newUser() internal returns (address user) {
        nextUserSeed++;
        user = address(uint160(0x100000 + nextUserSeed));
        token.mint(user, 1_000_000 ether);
    }

    // ── Action: register a new member via BFS ────────────────────────

    function action_register(uint8 sideSeed) public {
        address user = _newUser();

        // Find open slot
        try membership.findOpenSlot(address(this), 0) returns (
            address parent, BinaryMembershipV1.Side side
        ) {
            if (parent == address(0)) return;

            // Approve from user — Echidna calls as this contract, so we do
            // a direct token approval trick: mint to this contract and transfer
            // Actually: Echidna only calls as msg.sender = this contract
            // So we need the user's tokens approved. We use the mock mint + our transfer.
            // Simpler: pull tokens through this contract
            token.mint(address(this), FEE_0);
            token.approve(address(membership), FEE_0);

            membership.register(address(this), parent, side);
            // This will fail because address(this) is already registered.
            // We need a different approach for Echidna.
        } catch {}
    }

    // The above won't work well because Echidna always calls as the same
    // msg.sender (the test contract). Let's use a wrapper approach instead.

    // ── Wrapper members that proxy calls ─────────────────────────────

    EchidnaMember[] public proxyMembers;
    uint256 public proxyIdx;

    function _getNextProxy() internal returns (EchidnaMember) {
        if (proxyIdx >= proxyMembers.length) {
            EchidnaMember m = new EchidnaMember(membership, token);
            proxyMembers.push(m);
            token.mint(address(m), 1_000_000 ether);
            m.doApprove();
        }
        return proxyMembers[proxyIdx++];
    }

    // ── Real actions ─────────────────────────────────────────────────

    // NOTE: deliberately NOT named echidna_* — it mutates state, so Echidna
    // would list it as a trivially-passing property and inflate the count.

    function action_registerBFS() public {
        if (proxyIdx >= 80) return; // cap at 80 members to keep runs fast
        EchidnaMember m = _getNextProxy();

        try membership.findOpenSlot(address(this), 0) returns (
            address parent, BinaryMembershipV1.Side side
        ) {
            if (parent == address(0)) return;
            try m.doRegister(address(this), parent, side) {
                ghostFeesPulled += FEE_0;
                registeredMembers.push(address(m));
            } catch {}
        } catch {}
    }

    function action_enrollRootStage(uint8 stageRaw) public {
        uint256 stageId = (uint256(stageRaw) % 5) + 1; // 1..5
        try membership.enrollStageRoot(address(this), stageId) {} catch {}
    }

    function action_joinStage(uint8 memberIdx, uint8 stageRaw) public {
        if (registeredMembers.length == 0) return;
        uint256 idx = uint256(memberIdx) % registeredMembers.length;
        uint256 stageId = (uint256(stageRaw) % 5) + 1;

        address memberAddr = registeredMembers[idx];
        EchidnaMember m = EchidnaMember(memberAddr);

        try membership.findOpenSlot(address(this), stageId) returns (
            address parent, BinaryMembershipV1.Side side
        ) {
            if (parent == address(0)) return;
            BinaryMembershipV1.StageConfig memory config = membership.getStageConfig(stageId);
            token.mint(address(m), config.fee);
            m.doApprove();
            try m.doJoinStage(stageId, parent, side) {
                ghostFeesPulled += config.fee;
            } catch {}
        } catch {}
    }

    function action_withdrawTreasury(uint128 amountRaw) public {
        uint256 pending = membership.pendingTreasury();
        if (pending == 0) return;
        uint256 amount = (uint256(amountRaw) % pending) + 1;
        if (amount > pending) amount = pending;

        try membership.withdrawTreasury(amount) {
            ghostTreasuryWithdrawn += amount;
        } catch {}
    }

    function action_grantAward(uint8 memberIdx, uint8 stageRaw, uint128 amount) public {
        if (registeredMembers.length == 0) return;
        uint256 idx = uint256(memberIdx) % registeredMembers.length;
        uint256 stageId = uint256(stageRaw) % 6;
        uint256 amt = uint256(amount) % 10_000 ether;

        try membership.grantPhysicalAward(registeredMembers[idx], stageId, amt) {
            ghostAwardsPaid += amt;
        } catch {}
    }

    // ── Invariant 1: SOLVENCY ────────────────────────────────────────
    // Contract balance must always cover pending treasury obligations

    function echidna_solvency() public view returns (bool) {
        return token.balanceOf(address(membership)) >= membership.pendingTreasury();
    }

    // ── Invariant 2: FEE CONSERVATION ────────────────────────────────
    // Every fee pulled = pool paid + treasury accumulated

    function echidna_fee_conservation() public view returns (bool) {
        return ghostFeesPulled == membership.totalPoolPaid() + membership.totalTreasuryPaid();
    }

    // ── Invariant 3: TREASURY ACCOUNTING ─────────────────────────────
    // Pending = total accumulated - total withdrawn

    function echidna_treasury_accounting() public view returns (bool) {
        return membership.pendingTreasury() ==
            membership.totalTreasuryPaid() - ghostTreasuryWithdrawn;
    }

    // ── Invariant 4: BALANCE CONSERVATION ────────────────────────────
    // Contract balance = initial funding + fees in - pool out - treasury out - awards out

    function echidna_balance_conservation() public view returns (bool) {
        uint256 expected = INITIAL_FUNDING
            + ghostFeesPulled
            - membership.totalPoolPaid()
            - ghostTreasuryWithdrawn
            - ghostAwardsPaid;
        return token.balanceOf(address(membership)) == expected;
    }

    // ── Invariant 5: MEMBER COUNT ────────────────────────────────────
    // memberCount = root (this contract) + proxy members registered

    function echidna_member_count() public view returns (bool) {
        return membership.memberCount() == registeredMembers.length + 1;
    }

    // ── Invariant 6: A FULL-DEPTH PAYOUT NEVER EXCEEDS THE FEE ───────
    // Every upline on a board is paid, so the binding solvency condition is
    // treeDepth * nodeReward < fee, NOT the weaker nodeReward < fee.

    function echidna_full_depth_payout_under_fee() public view returns (bool) {
        for (uint256 i = 0; i < 6; i++) {
            BinaryMembershipV1.StageConfig memory c = membership.getStageConfig(i);
            if (c.nodeReward * c.treeDepth >= c.fee) return false;
        }
        return true;
    }

    // ── Invariant 7: POOL PAID MONOTONIC ─────────────────────────────
    // totalPoolPaid can never decrease

    uint256 internal lastPoolPaid;
    function echidna_pool_monotonic() public returns (bool) {
        uint256 current = membership.totalPoolPaid();
        if (current < lastPoolPaid) return false;
        lastPoolPaid = current;
        return true;
    }

    // ── Invariant 8: PENDING TREASURY <= CONTRACT BALANCE ────────────

    function echidna_pending_within_balance() public view returns (bool) {
        return membership.pendingTreasury() <= token.balanceOf(address(membership));
    }
}

/// @notice Proxy contract so each "member" has its own address for Echidna
contract EchidnaMember {
    BinaryMembershipV1 public membership;
    MockERC20 public token;

    constructor(BinaryMembershipV1 _membership, MockERC20 _token) {
        membership = _membership;
        token = _token;
    }

    function doApprove() external {
        token.approve(address(membership), type(uint256).max);
    }

    function doRegister(
        address sponsor,
        address parent,
        BinaryMembershipV1.Side side
    ) external {
        membership.register(sponsor, parent, side);
    }

    function doJoinStage(
        uint256 stageId,
        address parent,
        BinaryMembershipV1.Side side
    ) external {
        membership.joinStage(stageId, parent, side);
    }
}
