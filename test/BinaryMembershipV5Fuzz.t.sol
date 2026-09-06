// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BinaryMembershipV5} from "../src/BinaryMembershipV5.sol";
import {MockUSDT18} from "../src/MockUSDT18.sol";

/// @dev Exposes V5's overridden `_creditTreasury` so its split math can be
/// fuzzed in isolation without going through the whole registration flow.
contract V5CreditHarness is BinaryMembershipV5 {
    constructor(
        IERC20 _asset,
        address _treasury,
        address _companyWallet,
        address _admin,
        uint48 _adminDelay,
        address _designatedRoot
    )
        BinaryMembershipV5(_asset, _treasury, _companyWallet, _admin, _adminDelay, _designatedRoot)
    {}

    /// @notice Callable proxy for `_creditTreasury`. Tests are the only
    /// intended caller; production entry paths still use the internal function.
    function exposedCreditTreasury(uint256 amount) external {
        _creditTreasury(amount);
    }
}

/// @notice Fuzz suite for V5's immediate treasury/company split rule.
/// @dev Verifies the four properties that make the split safe:
///      1. No wei is lost or created                       (sum invariance)
///      2. Company never receives more than half           (rounding rule)
///      3. Treasury receives at most one extra base unit   (rounding bound)
///      4. `totalTreasuryPaid` tracks the pre-split total  (accounting)
///      5. `pendingTreasury` is untouched by entry credits (V5 design)
contract BinaryMembershipV5FuzzTest is Test {
    address internal constant ADMIN = address(0xA11CE);
    address internal constant TREASURY = address(0x7000);
    address internal constant COMPANY = address(0x8000);
    address internal constant ROOT = address(0x1000);

    MockUSDT18 internal usdt;
    V5CreditHarness internal harness;

    function setUp() public {
        usdt = new MockUSDT18(ADMIN);
        harness = new V5CreditHarness(
            IERC20(address(usdt)),
            TREASURY,
            COMPANY,
            ADMIN,
            0,
            ROOT
        );
    }

    // ── Property fuzzers ─────────────────────────────────────────────────

    /// @notice The split preserves every wei: treasury + company == amount.
    function testFuzz_SplitConservesTotal(uint256 amount) public {
        // Bound to a realistic protocol maximum (10 million USDT-18) so the
        // mock's mint doesn't overflow and fuzzing stays inside the domain
        // where entry credits actually occur.
        amount = bound(amount, 0, 10_000_000 ether);

        _fund(amount);
        uint256 tBefore = usdt.balanceOf(TREASURY);
        uint256 cBefore = usdt.balanceOf(COMPANY);

        harness.exposedCreditTreasury(amount);

        uint256 tDelta = usdt.balanceOf(TREASURY) - tBefore;
        uint256 cDelta = usdt.balanceOf(COMPANY) - cBefore;
        assertEq(tDelta + cDelta, amount, "split lost or created wei");
    }

    /// @notice Company can never receive more than half of any credit.
    function testFuzz_CompanyNeverExceedsHalf(uint256 amount) public {
        amount = bound(amount, 0, 10_000_000 ether);

        _fund(amount);
        uint256 tBefore = usdt.balanceOf(TREASURY);
        uint256 cBefore = usdt.balanceOf(COMPANY);

        harness.exposedCreditTreasury(amount);

        uint256 tDelta = usdt.balanceOf(TREASURY) - tBefore;
        uint256 cDelta = usdt.balanceOf(COMPANY) - cBefore;
        assertLe(cDelta, tDelta, "company received more than treasury");
        // The gap is at most a single base unit (indivisible remainder).
        assertLe(tDelta - cDelta, 1, "split gap exceeded one base unit");
    }

    /// @notice `totalTreasuryPaid` reflects the pre-split amount.
    function testFuzz_TotalTreasuryPaidTracksInput(uint256 amount) public {
        amount = bound(amount, 0, 10_000_000 ether);

        _fund(amount);
        uint256 before = harness.totalTreasuryPaid();

        harness.exposedCreditTreasury(amount);

        assertEq(
            harness.totalTreasuryPaid() - before,
            amount,
            "totalTreasuryPaid drifted from input"
        );
    }

    /// @notice V5 auto-split MUST NOT enqueue entry credits into
    /// `pendingTreasury` — that reserve is reserved for `fundTreasury`.
    function testFuzz_PendingTreasuryUntouched(uint256 amount) public {
        amount = bound(amount, 1, 10_000_000 ether);

        _fund(amount);
        uint256 pendingBefore = harness.pendingTreasury();

        harness.exposedCreditTreasury(amount);

        assertEq(
            harness.pendingTreasury(),
            pendingBefore,
            "V5 entry credit leaked into pendingTreasury"
        );
    }

    /// @notice Repeated credits sum exactly across calls.
    function testFuzz_MultipleCreditsSum(uint256[8] calldata seeds) public {
        uint256 running;
        uint256 iterations;
        for (uint256 i = 0; i < seeds.length; i++) {
            uint256 amount = bound(seeds[i], 0, 1_000_000 ether);
            _fund(amount);
            harness.exposedCreditTreasury(amount);
            running += amount;
            iterations++;
        }
        assertEq(
            usdt.balanceOf(TREASURY) + usdt.balanceOf(COMPANY),
            running,
            "cumulative wallets don't match total credited"
        );
        assertEq(
            harness.totalTreasuryPaid(),
            running,
            "totalTreasuryPaid drifted across calls"
        );
        // Cumulative gap can grow at most one per odd-amount call.
        uint256 tBal = usdt.balanceOf(TREASURY);
        uint256 cBal = usdt.balanceOf(COMPANY);
        assertLe(cBal, tBal, "cumulative company beat treasury");
        assertLe(tBal - cBal, iterations, "cumulative gap exceeded call count");
    }

    // ── Boundary + degenerate cases ──────────────────────────────────────

    function test_ZeroAmountIsSafe() public {
        uint256 tBefore = usdt.balanceOf(TREASURY);
        uint256 cBefore = usdt.balanceOf(COMPANY);
        uint256 pendingBefore = harness.pendingTreasury();
        uint256 totalBefore = harness.totalTreasuryPaid();

        harness.exposedCreditTreasury(0);

        assertEq(usdt.balanceOf(TREASURY), tBefore, "treasury shifted on zero credit");
        assertEq(usdt.balanceOf(COMPANY), cBefore, "company shifted on zero credit");
        assertEq(harness.pendingTreasury(), pendingBefore, "pending shifted on zero credit");
        assertEq(harness.totalTreasuryPaid(), totalBefore, "total drifted on zero credit");
    }

    function test_OneWeiCreditGoesToTreasury() public {
        _fund(1);
        harness.exposedCreditTreasury(1);
        assertEq(usdt.balanceOf(TREASURY), 1, "single wei went to wrong wallet");
        assertEq(usdt.balanceOf(COMPANY), 0, "company received an unsplittable wei");
    }

    // ── Helpers ──────────────────────────────────────────────────────────

    function _fund(uint256 amount) internal {
        if (amount == 0) return;
        vm.prank(ADMIN);
        usdt.mint(address(harness), amount);
    }
}
