// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice How the rollover-to-award threshold behaves when it is retuned on a
///         live system.
///
///  It is admin-configurable per stage, at deployment and at any time after.
///  The part that is not obvious is what happens to members who ALREADY have
///  rollovers banked when the number moves, which is what these tests pin down.
contract BinaryMembershipV1AwardThresholdTest is Test {
    BinaryMembershipV1 internal m;
    MockERC20 internal token;

    address internal constant ADMIN = address(0xAD);
    address internal constant TREASURY = address(0x7EA5);
    address internal constant OPERATOR = address(0x0B);
    address internal constant ROOT = address(0x1);

    uint256[6] FEES   = [uint256(20 ether), 60 ether, 180 ether, 540 ether, 1620 ether, 4860 ether];
    uint256[6] NODES  = [uint256(5 ether), 10 ether, 25 ether, 80 ether, 250 ether, 800 ether];
    uint256[6] SLOTS  = [uint256(6), 14, 14, 14, 14, 14];
    uint256[6] DEPTHS = [uint256(2), 3, 3, 3, 3, 3];
    uint256[6] AWARDS = [uint256(0), 10, 10, 10, 10, 8];

    function setUp() public {
        token = new MockERC20("FAKEUSD", "FUSD", 0);

        vm.startPrank(ADMIN);
        m = new BinaryMembershipV1(IERC20(address(token)), TREASURY, ADMIN, 0, ROOT);
        m.grantRole(m.OPERATOR_ROLE(), OPERATOR);
        m.grantRole(m.TREASURY_ROLE(), TREASURY);
        m.configureStages(FEES, NODES, SLOTS, DEPTHS, AWARDS);
        vm.stopPrank();

        token.mint(ROOT, 1_000_000 ether);
        vm.prank(ROOT);
        token.approve(address(m), type(uint256).max);
        vm.prank(ROOT);
        m.register(address(0), address(0), BinaryMembershipV1.Side.None);
    }

    function _u(uint256 i) internal pure returns (address) {
        return address(uint160(0xD00000 + i));
    }

    /// @dev Build enough stage-1 volume under ROOT to bank plenty of rollovers.
    function _buildRollovers(uint256 count) internal {
        for (uint256 i = 0; i < count; i++) {
            address u = _u(i);
            token.mint(u, 100_000 ether);
            vm.prank(u);
            token.approve(address(m), type(uint256).max);
            (address p, BinaryMembershipV1.Side s) = m.findPlacementSlot(ROOT, 0);
            vm.prank(u);
            m.register(ROOT, p, s);
        }

        vm.prank(OPERATOR);
        m.enrollStageRoot(ROOT, 1);
        for (uint256 i = 0; i < count; i++) {
            (address p, BinaryMembershipV1.Side s) = m.findPlacementSlot(ROOT, 1);
            vm.prank(_u(i));
            m.joinStage(1, p, s);
        }
    }

    // ══════════════════════════════════════════════════════════════════

    /// @notice The threshold is per stage and settable at any time by admin.
    function test_Threshold_IsConfigurablePerStage() public {
        assertEq(m.getStageConfig(1).rolloversForAward, 10, "deploy value");

        vm.prank(ADMIN);
        m.updateAwardThreshold(1, 4);
        assertEq(m.getStageConfig(1).rolloversForAward, 4, "not lowered");

        vm.prank(ADMIN);
        m.updateAwardThreshold(1, 25);
        assertEq(m.getStageConfig(1).rolloversForAward, 25, "not raised");

        // Other stages are untouched.
        assertEq(m.getStageConfig(2).rolloversForAward, 10, "stage 2 moved");

        // Admin only.
        vm.prank(OPERATOR);
        vm.expectRevert();
        m.updateAwardThreshold(1, 3);
    }

    /// @notice Setting the threshold to 0 disables awards for that stage
    ///         entirely — the same state stage 0 ships in.
    function test_Threshold_ZeroDisablesAwardsForThatStage() public {
        _buildRollovers(160);

        vm.prank(ADMIN);
        m.updateAwardThreshold(1, 0);

        (,,,, bool eligible) = m.getAwardInfo(ROOT, 1);
        assertFalse(eligible, "zero threshold should never be eligible");

        vm.prank(OPERATOR);
        vm.expectRevert(
            abi.encodeWithSelector(BinaryMembershipV1.InvalidStage.selector, uint256(1))
        );
        m.grantPhysicalAward(ROOT, 1, 1 ether);
    }

    /// @notice RAISING the threshold can make an already-eligible member
    ///         ineligible again. Nothing is lost — the rollovers stay banked —
    ///         but a member who could claim yesterday cannot claim today.
    function test_Threshold_RaisingCanRevokeEligibility() public {
        _buildRollovers(160);

        (,, uint256 rollovers,, bool eligibleBefore) = m.getAwardInfo(ROOT, 1);
        assertTrue(eligibleBefore, "should start eligible at threshold 10");
        console.log("rollovers banked:", rollovers);

        vm.prank(ADMIN);
        m.updateAwardThreshold(1, rollovers + 5);

        (,,, uint256 milestone, bool eligibleAfter) = m.getAwardInfo(ROOT, 1);
        assertFalse(eligibleAfter, "raising should revoke eligibility");
        assertEq(milestone, rollovers + 5, "milestone follows the new threshold");

        vm.prank(OPERATOR);
        vm.expectRevert();
        m.grantPhysicalAward(ROOT, 1, 1 ether);
    }

    /// @notice LOWERING the threshold creates an immediate BACKLOG of claimable
    ///         awards for anyone holding unclaimed rollovers.
    ///
    ///  This is the operationally important one. A member sitting on 12
    ///  rollovers with the threshold at 10 has one award due. Drop the
    ///  threshold to 3 and they are suddenly owed four, all payable at once,
    ///  because each grant only advances the milestone by one threshold.
    function test_Threshold_LoweringCreatesAnImmediateBacklog() public {
        _buildRollovers(160);

        (,, uint256 rollovers,,) = m.getAwardInfo(ROOT, 1);
        console.log("rollovers banked:", rollovers);
        assertGe(rollovers, 10, "need a real bank of rollovers");

        // Award value is capped against earnings, so use a small figure and
        // count how many separate grants become possible.
        uint256 perAward = 1 ether;

        vm.prank(ADMIN);
        m.updateAwardThreshold(1, 3);

        uint256 granted;
        for (uint256 i = 0; i < 50; i++) {
            (,,,, bool eligible) = m.getAwardInfo(ROOT, 1);
            if (!eligible) break;
            vm.prank(OPERATOR);
            try m.grantPhysicalAward(ROOT, 1, perAward) {
                granted++;
            } catch {
                break;
            }
        }

        console.log("threshold lowered 10 -> 3");
        console.log("awards immediately claimable:", granted);
        assertGt(granted, 1, "lowering should unlock more than one award");
        assertEq(granted, rollovers / 3, "one award per completed new milestone");
    }

    /// @notice The earnings cap still binds no matter how low the threshold
    ///         goes, so lowering it cannot be used to drain the treasury.
    function test_Threshold_LoweringCannotBypassTheEarningsCap() public {
        _buildRollovers(160);

        uint256 earnings = m.getStageMembership(ROOT, 1).stageEarnings;

        // Cap awards at 25% of what the board actually generated.
        vm.prank(ADMIN);
        m.setAwardCapBps(2_500);
        uint256 ceiling = (earnings * 2_500) / 10_000;

        // Then drop the threshold to the minimum to maximise claim count.
        vm.prank(ADMIN);
        m.updateAwardThreshold(1, 1);

        // Grant repeatedly until something stops it.
        for (uint256 i = 0; i < 200; i++) {
            (,,,, bool eligible) = m.getAwardInfo(ROOT, 1);
            if (!eligible) break;
            vm.prank(OPERATOR);
            try m.grantPhysicalAward(ROOT, 1, ceiling) {} catch { break; }
        }

        uint256 paid = m.getStageMembership(ROOT, 1).totalAwarded;
        console.log("stage earnings   (USD):", earnings / 1 ether);
        console.log("cap at 25%       (USD):", ceiling / 1 ether);
        console.log("total awarded    (USD):", paid / 1 ether);

        assertLe(paid, ceiling, "cumulative awards escaped the earnings cap");
    }
}
