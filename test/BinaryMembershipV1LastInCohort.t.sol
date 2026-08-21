// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice What happens to the people who join last.
///
///  Every matrix plan has an answer to this and it is always the same one, so
///  it is better measured than argued about. These tests report, by join order,
///  who a member pays and what they get back — with no assertion that the
///  outcome is good, only that the figures are real.
contract BinaryMembershipV1LastInCohortTest is Test {
    BinaryMembershipV1 internal m;
    MockERC20 internal token;

    address internal constant ADMIN = address(0xAD);
    address internal constant TREASURY = address(0x7EA5);
    address internal constant OPERATOR = address(0x0B);
    address internal constant ROOT = address(0x1);

    uint256 constant WALLETS = 600;

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
        m.setCycleGuardEnabled(true);
        vm.stopPrank();

        token.mint(ROOT, 1_000_000 ether);
        vm.prank(ROOT);
        token.approve(address(m), type(uint256).max);
        vm.prank(ROOT);
        m.register(address(0), address(0), BinaryMembershipV1.Side.None);

        for (uint256 i = 0; i < WALLETS; i++) {
            address u = _u(i);
            token.mint(u, 100_000 ether);
            vm.prank(u);
            token.approve(address(m), type(uint256).max);
        }
    }

    function _u(uint256 i) internal pure returns (address) {
        return address(uint160(0xF00000 + i));
    }

    /// @dev Concentrated recruiters, matching how real programmes actually grow.
    function _sponsorOf(uint256 i) internal pure returns (address) {
        if (i < 3) return ROOT;
        return _u(i % 3);
    }

    function _usd(uint256 x) internal pure returns (uint256) { return x / 1 ether; }

    // ══════════════════════════════════════════════════════════════════

    /// @notice Who does a joiner pay, and how much of their fee leaves the
    ///         member pool entirely?
    function test_LastIn_WhoDoesAJoinerPay() public {
        // Seed a deep-enough tree that a new joiner has a full set of uplines.
        for (uint256 i = 0; i < 100; i++) {
            (address p, BinaryMembershipV1.Side s) = m.findPlacementSlot(_sponsorOf(i), 0);
            vm.prank(_u(i));
            m.register(_sponsorOf(i), p, s);
        }

        uint256 poolBefore = m.totalPoolPaid();
        uint256 treasuryBefore = m.pendingTreasury();

        (address parent, BinaryMembershipV1.Side side) = m.findPlacementSlot(_sponsorOf(100), 0);
        vm.prank(_u(100));
        m.register(_sponsorOf(100), parent, side);

        uint256 toUplines = m.totalPoolPaid() - poolBefore;
        uint256 toTreasury = m.pendingTreasury() - treasuryBefore;

        console.log("=== ONE STAGE-1 JOIN ($20 fee) ===");
        console.log("  paid to uplines (USD):", _usd(toUplines));
        console.log("  paid to treasury(USD):", _usd(toTreasury));
        console.log("  uplines paid         :", toUplines / NODES[0]);

        assertEq(toUplines + toTreasury, FEES[0], "fee must split exactly");

        // A joiner pays at most treeDepth uplines; the rest is treasury's.
        assertLe(toUplines, DEPTHS[0] * NODES[0], "paid more uplines than the board is deep");
    }

    /// @notice Earnings by join order. The question is whether the last cohort
    ///         earns anything at all, so measure the first, middle and last.
    function test_LastIn_EarningsByJoinOrder() public {
        for (uint256 i = 0; i < WALLETS; i++) {
            (address p, BinaryMembershipV1.Side s) = m.findPlacementSlot(_sponsorOf(i), 0);
            vm.prank(_u(i));
            m.register(_sponsorOf(i), p, s);
        }

        uint256 firstThird = _cohortEarnings(0, WALLETS / 3);
        uint256 middleThird = _cohortEarnings(WALLETS / 3, (WALLETS * 2) / 3);
        uint256 lastThird = _cohortEarnings((WALLETS * 2) / 3, WALLETS);

        uint256 zeroInLast = _cohortZeroEarners((WALLETS * 2) / 3, WALLETS);
        uint256 zeroOverall = _cohortZeroEarners(0, WALLETS);
        uint256 lastHundredZero = _cohortZeroEarners(WALLETS - 100, WALLETS);

        console.log("=== STAGE-1 EARNINGS BY JOIN ORDER (600 members) ===");
        console.log("  first third  earned (USD):", _usd(firstThird));
        console.log("  middle third earned (USD):", _usd(middleThird));
        console.log("  last third   earned (USD):", _usd(lastThird));
        console.log("");
        console.log("  members earning $0, overall :", zeroOverall, "of", WALLETS);
        console.log("  members earning $0, last 200:", zeroInLast);
        console.log("  members earning $0, last 100:", lastHundredZero);
        console.log("");
        console.log("  each of them paid (USD):", _usd(FEES[0]));
        console.log("  total paid by the last 100 (USD):", _usd(100 * FEES[0]));

        // The structural claim: earning is a function of who joins AFTER you.
        assertGt(firstThird, lastThird, "earlier cohorts should out-earn later ones");

        // And the last arrivals have nobody beneath them at all.
        assertGt(lastHundredZero, 0, "expected some of the final cohort to earn nothing");
    }

    /// @notice The system-wide split: how much of everything collected ever
    ///         reaches members, versus how much is retained.
    function test_LastIn_SystemWideSplit() public {
        for (uint256 i = 0; i < WALLETS; i++) {
            (address p, BinaryMembershipV1.Side s) = m.findPlacementSlot(_sponsorOf(i), 0);
            vm.prank(_u(i));
            m.register(_sponsorOf(i), p, s);
        }

        uint256 fees = WALLETS * FEES[0];
        uint256 pool = m.totalPoolPaid();
        uint256 treasury = m.pendingTreasury();

        console.log("=== WHERE $12,000 OF STAGE-1 FEES WENT ===");
        console.log("  collected      (USD):", _usd(fees));
        console.log("  to members     (USD):", _usd(pool), "=", (pool * 100) / fees);
        console.log("  to treasury    (USD):", _usd(treasury), "=", (treasury * 100) / fees);

        assertEq(pool + treasury, fees, "conservation");

        // Members can never collectively receive more than they paid in: the
        // treasury share is a hard leak out of the member pool.
        assertLt(pool, fees, "member payouts cannot exceed member deposits");
    }

    function _cohortEarnings(uint256 from, uint256 to) internal view returns (uint256 total) {
        for (uint256 i = from; i < to; i++) {
            total += m.getStageMembership(_u(i), 0).stageEarnings;
        }
    }

    function _cohortZeroEarners(uint256 from, uint256 to) internal view returns (uint256 n) {
        for (uint256 i = from; i < to; i++) {
            if (m.getStageMembership(_u(i), 0).stageEarnings == 0) n++;
        }
    }
}
