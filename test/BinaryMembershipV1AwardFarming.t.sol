// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Measures the exact cost of self-funding your way to the physical
///         award threshold using sock-puppet wallets you control.
///
///  grantPhysicalAward only checks `rolloverCount >= rolloversForAward`.
///  rolloverCount is driven purely by placements below you — it does not
///  distinguish real recruits from wallets the same person owns.
///
///  This is not a fund-drain: the award is OPERATOR-gated, so a human still
///  approves it. The point is to price the attack so the award value can be
///  set below the cost of faking it.
contract BinaryMembershipV1AwardFarmingTest is Test {
    BinaryMembershipV1 public membership;
    MockERC20 public token;

    address admin = address(0xAD);
    address treasuryWallet = address(0x7EA5);
    address operator = address(0x0B);

    address root = address(0x1);
    address attacker = address(0xA77ACC);

    // Sock puppets the attacker controls
    address[] public puppets;
    uint256 constant PUPPETS = 160;

    uint256 constant FEE_0 = 20 ether;
    uint256 constant FEE_1 = 60 ether;
    uint256 constant NODE_0 = 5 ether;
    uint256 constant NODE_1 = 10 ether;

    function setUp() public {
        token = new MockERC20("FAKEUSD", "FUSD", 0);

        vm.startPrank(admin);
        membership = new BinaryMembershipV1(
            IERC20(address(token)), treasuryWallet, admin, 0, root
        );
        membership.grantRole(membership.OPERATOR_ROLE(), operator);
        membership.grantRole(membership.TREASURY_ROLE(), treasuryWallet);

        membership.configureStages(
            [uint256(20 ether), 60 ether, 180 ether, 540 ether, 1620 ether, 4860 ether],
            [uint256(5 ether), 10 ether, 25 ether, 80 ether, 250 ether, 800 ether],
            [uint256(6), 14, 14, 14, 14, 14],
            [uint256(2), 3, 3, 3, 3, 3],
            [uint256(0), 10, 10, 10, 10, 8]
        );
        vm.stopPrank();

        token.mint(address(membership), 5_000_000 ether);

        vm.prank(root);
        membership.register(address(0), address(0), BinaryMembershipV1.Side.None);

        // Attacker joins normally under root
        token.mint(attacker, 1_000_000 ether);
        vm.prank(attacker);
        token.approve(address(membership), type(uint256).max);

        (address p, BinaryMembershipV1.Side s) = membership.findOpenSlot(root, 0);
        vm.prank(attacker);
        membership.register(root, p, s);

        // Fund puppets from the attacker's own budget
        for (uint256 i = 0; i < PUPPETS; i++) {
            address pup = address(uint160(0x300000 + i));
            puppets.push(pup);
            token.mint(pup, 100_000 ether);
            vm.prank(pup);
            token.approve(address(membership), type(uint256).max);
        }
    }

    function test_AwardFarming_CostToFakeTenRollovers() public {
        console.log("=========================================================");
        console.log("  COST TO SELF-FARM A STAGE-1 PHYSICAL AWARD");
        console.log("=========================================================");

        // Total tokens across every address the attacker controls, before
        uint256 before = _attackerNetWorth();

        // ── Step 1: puppets register at stage 0 under the attacker ───
        // They must be stage-0 members before they can join stage 1.
        uint256 registered;
        for (uint256 i = 0; i < 140; i++) {
            (address parent, BinaryMembershipV1.Side side) =
                membership.findOpenSlot(attacker, 0);
            if (parent == address(0)) break;

            vm.prank(puppets[i]);
            membership.register(attacker, parent, side);
            registered++;
        }
        console.log("  puppets registered at stage 0: %d", registered);

        // ── Step 2: attacker enrolls at stage 1 as a tree root ───────
        vm.prank(operator);
        membership.enrollStageRoot(attacker, 1);

        // ── Step 3: puppets fill the attacker's stage-1 tree ─────────
        // 10 rollovers x 14 slots = 140 placements.
        uint256 joined;
        for (uint256 i = 0; i < 140; i++) {
            (address parent, BinaryMembershipV1.Side side) =
                membership.findOpenSlot(attacker, 1);
            if (parent == address(0)) break;

            vm.prank(puppets[i]);
            membership.joinStage(1, parent, side);
            joined++;
        }
        console.log("  puppets joined at stage 1:     %d", joined);

        // ── Step 4: threshold reached? ───────────────────────────────
        (,,, uint256 rollovers,,) = membership.getTreeInfo(attacker, 1);
        console.log("  attacker stage-1 rollovers:    %d", rollovers);

        uint256 threshold = membership.getStageConfig(1).rolloversForAward;
        console.log("  award threshold:               %d", threshold);

        assertGe(
            rollovers,
            threshold,
            "FARMING FAILED: could not reach threshold with sock puppets"
        );

        // The rollover gate passes for a purely self-funded board — that part
        // is unchanged and unfixable on-chain. What stops the attack paying is
        // the award cap, so the most that can be extracted is the capped value.
        (,,,,, uint256 stageEarnings) = membership.getTreeInfo(attacker, 1);
        uint256 awardValue = (stageEarnings * membership.awardCapBps()) / 10_000;

        vm.prank(operator);
        membership.grantPhysicalAward(attacker, 1, awardValue);

        uint256 afterNet = _attackerNetWorth();

        // Net cost = what the whole controlled cluster spent, minus the award
        uint256 spentIncludingAward = before - afterNet;

        console.log("");
        console.log("  --- ECONOMICS ---");
        console.log("  net cost incl. award received: %d FUSD", spentIncludingAward / 1 ether);
        console.log("  award value granted:           %d FUSD", awardValue / 1 ether);
        console.log("  cost to fake, net of award:    %d FUSD",
            (spentIncludingAward + awardValue) / 1 ether);
        console.log("");
        console.log("  => An award worth MORE than the net cost is profitable");
        console.log("     to farm. Keep award value below this number, or");
        console.log("     gate grants on off-chain proof of real recruits.");

        // Solvency is never at risk from this - it is an economics issue.
        assertGe(
            token.balanceOf(address(membership)),
            membership.pendingTreasury(),
            "insolvent"
        );
    }

    /// @dev Same idea but confirms the OPERATOR gate is the actual defence:
    ///      nobody without the role can trigger the payout, however many
    ///      rollovers they have farmed.
    function test_AwardFarming_OperatorGateIsTheDefence() public {
        for (uint256 i = 0; i < 140; i++) {
            (address parent, BinaryMembershipV1.Side side) =
                membership.findOpenSlot(attacker, 0);
            if (parent == address(0)) break;
            vm.prank(puppets[i]);
            membership.register(attacker, parent, side);
        }

        vm.prank(operator);
        membership.enrollStageRoot(attacker, 1);

        for (uint256 i = 0; i < 140; i++) {
            (address parent, BinaryMembershipV1.Side side) =
                membership.findOpenSlot(attacker, 1);
            if (parent == address(0)) break;
            vm.prank(puppets[i]);
            membership.joinStage(1, parent, side);
        }

        (,,, uint256 rollovers,,) = membership.getTreeInfo(attacker, 1);
        assertGe(
            rollovers,
            membership.getStageConfig(1).rolloversForAward,
            "threshold not reached"
        );

        // Attacker has the rollovers but cannot pay themselves.
        vm.expectRevert();
        vm.prank(attacker);
        membership.grantPhysicalAward(attacker, 1, 1_000 ether);

        // Neither can any puppet.
        vm.expectRevert();
        vm.prank(puppets[0]);
        membership.grantPhysicalAward(attacker, 1, 1_000 ether);
    }

    // ══════════════════════════════════════════════════════════════════
    //  THE PATCH: award capped at a share of real stage earnings
    // ══════════════════════════════════════════════════════════════════

    /// @notice With the cap in place, farming cannot pay for itself. The
    ///         farmer's cost scales with the board they had to fund; the award
    ///         scales with what that board earned them, which is strictly less.
    function test_AwardCap_MakesFarmingUnprofitable() public {
        uint256 before = _attackerNetWorth();

        _farmToThreshold();

        (,,,,, uint256 stageEarnings) = membership.getTreeInfo(attacker, 1);
        uint256 maxAward = (stageEarnings * membership.awardCapBps()) / 10_000;

        // Anything above the earnings-based ceiling is refused outright.
        vm.expectRevert(
            abi.encodeWithSelector(
                BinaryMembershipV1.AwardExceedsCap.selector, maxAward, maxAward + 1
            )
        );
        vm.prank(operator);
        membership.grantPhysicalAward(attacker, 1, maxAward + 1);

        // Take the maximum the cap allows
        vm.prank(operator);
        membership.grantPhysicalAward(attacker, 1, maxAward);

        uint256 afterNet = _attackerNetWorth();

        console.log("=========================================================");
        console.log("  AWARD CAP vs FARMING");
        console.log("=========================================================");
        console.log("  attacker stage-1 earnings: %d FUSD", stageEarnings / 1 ether);
        console.log("  max award under cap:       %d FUSD", maxAward / 1 ether);
        console.log("  net LOSS after max award:  %d FUSD", (before - afterNet) / 1 ether);

        // Even taking the largest award allowed, the farmer ends down.
        assertLt(afterNet, before, "FARMING STILL PROFITABLE: cap is too generous");
    }

    /// @notice The cap must not punish a genuine member. They pay one join fee
    ///         and their downline funds itself, so they end far ahead.
    function test_AwardCap_GenuineMemberStillProfits() public {
        _farmToThreshold(); // same board shape; the difference is who paid

        (,,,,, uint256 stageEarnings) = membership.getTreeInfo(attacker, 1);
        uint256 maxAward = (stageEarnings * membership.awardCapBps()) / 10_000;

        // A genuine board owner's outlay is their own stage-0 + stage-1 joins.
        uint256 genuineCost = FEE_0 + FEE_1;
        uint256 genuineGain = stageEarnings + maxAward;

        console.log("  genuine member outlay: %d FUSD", genuineCost / 1 ether);
        console.log("  genuine member gain:   %d FUSD", genuineGain / 1 ether);

        assertGt(
            genuineGain,
            genuineCost * 10,
            "cap should leave genuine members far ahead"
        );
    }

    /// @notice The cap cannot be raised past 100%, which is what keeps the
    ///         unprofitability guarantee structural rather than a policy choice.
    function test_AwardCap_CannotExceed100Percent() public {
        vm.expectRevert(
            abi.encodeWithSelector(BinaryMembershipV1.InvalidAwardCap.selector, uint256(10_001))
        );
        vm.prank(admin);
        membership.setAwardCapBps(10_001);

        vm.prank(admin);
        membership.setAwardCapBps(10_000); // exactly 100% is allowed

        vm.prank(admin);
        membership.setAwardCapBps(2_500); // tightening is allowed
        assertEq(membership.awardCapBps(), 2_500);

        // Non-admin cannot touch it
        vm.expectRevert();
        vm.prank(attacker);
        membership.setAwardCapBps(10_000);
    }

    function _farmToThreshold() internal {
        for (uint256 i = 0; i < 140; i++) {
            (address parent, BinaryMembershipV1.Side side) =
                membership.findOpenSlot(attacker, 0);
            if (parent == address(0)) break;
            vm.prank(puppets[i]);
            membership.register(attacker, parent, side);
        }

        vm.prank(operator);
        membership.enrollStageRoot(attacker, 1);

        for (uint256 i = 0; i < 140; i++) {
            (address parent, BinaryMembershipV1.Side side) =
                membership.findOpenSlot(attacker, 1);
            if (parent == address(0)) break;
            vm.prank(puppets[i]);
            membership.joinStage(1, parent, side);
        }
    }

    function _attackerNetWorth() internal view returns (uint256 total) {
        total = token.balanceOf(attacker);
        for (uint256 i = 0; i < puppets.length; i++) {
            total += token.balanceOf(puppets[i]);
        }
    }
}
