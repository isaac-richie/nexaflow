// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, StdInvariant} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BinaryMembershipV5} from "../src/BinaryMembershipV5.sol";
import {MockUSDT18} from "../src/MockUSDT18.sol";

/// @dev Same harness shape as the fuzz suite: exposes `_creditTreasury` and
/// mints assets on demand so the invariant handler can drive random ops.
contract V5InvariantHarness is BinaryMembershipV5 {
    MockUSDT18 public immutable mockAsset;

    constructor(
        MockUSDT18 _asset,
        address _treasury,
        address _companyWallet,
        address _admin,
        uint48 _adminDelay,
        address _designatedRoot
    )
        BinaryMembershipV5(IERC20(address(_asset)), _treasury, _companyWallet, _admin, _adminDelay, _designatedRoot)
    {
        mockAsset = _asset;
    }

    function exposedCreditTreasury(uint256 amount) external {
        _creditTreasury(amount);
    }
}

/// @notice Handler that drives random V5 credit and fund operations and lets
/// the invariant engine hunt for a state where the auto-split accounting or
/// wallet-parity rules break.
contract V5Handler is Test {
    V5InvariantHarness public h;
    MockUSDT18 public token;
    address public admin;
    address public treasuryRole;

    // ghosts
    uint256 public ghostCreditedTotal;
    uint256 public ghostFundedTotal;
    uint256 public ghostWithdrawnTotal;
    uint256 public creditCallCount;
    uint256 public withdrawCallCount;

    constructor(
        V5InvariantHarness _h,
        MockUSDT18 _token,
        address _admin,
        address _treasuryRole
    ) {
        h = _h;
        token = _token;
        admin = _admin;
        treasuryRole = _treasuryRole;
    }

    /// Drive an entry-style credit. Amount bounded so total minted across a
    /// full invariant run stays inside a realistic protocol budget.
    function credit(uint256 rawAmount) external {
        uint256 amount = bound(rawAmount, 0, 500_000 ether);
        if (amount > 0) {
            vm.prank(admin);
            token.mint(address(h), amount);
        }
        h.exposedCreditTreasury(amount);
        ghostCreditedTotal += amount;
        creditCallCount++;
    }

    /// Drive an external award-reserve deposit via `fundTreasury`.
    function fundReserve(uint256 rawAmount) external {
        uint256 amount = bound(rawAmount, 0, 100_000 ether);
        if (amount == 0) return;
        vm.prank(admin);
        token.mint(address(this), amount);
        token.approve(address(h), amount);
        h.fundTreasury(amount);
        ghostFundedTotal += amount;
    }

    /// Drive a treasury withdrawal (splits pending 50/50 to treasury/company).
    function withdrawReserve(uint256 rawAmount) external {
        uint256 pending = h.pendingTreasury();
        if (pending == 0) return;
        uint256 amount = bound(rawAmount, 1, pending);
        vm.prank(treasuryRole);
        h.withdrawTreasury(amount);
        ghostWithdrawnTotal += amount;
        withdrawCallCount++;
    }
}

/// @notice Invariant suite for V5.
/// @dev Guarantees under random ops:
///      A) The contract never silently retains USDT — its balance equals
///         `pendingTreasury` (award reserve) at all times.
///      B) Every credited wei reaches treasury + company wallets in the same
///         transaction (no accumulation into `pendingTreasury`).
///      C) The wallet gap is bounded: `treasury >= company`, and the gap
///         cannot exceed the number of odd-remainder split operations, so
///         `treasury - company <= creditCallCount + withdrawCallCount`.
///      D) `totalTreasuryPaid` matches the pre-split sum of everything the
///         protocol pushed through the treasury path (credits + external
///         fundings).
contract BinaryMembershipV5InvariantTest is StdInvariant, Test {
    address internal constant ADMIN = address(0xA11CE);
    address internal constant TREASURY = address(0x7000);
    address internal constant COMPANY = address(0x8000);
    address internal constant ROOT = address(0x1000);

    MockUSDT18 internal usdt;
    V5InvariantHarness internal membership;
    V5Handler internal handler;

    function setUp() public {
        usdt = new MockUSDT18(ADMIN);
        membership = new V5InvariantHarness(usdt, TREASURY, COMPANY, ADMIN, 0, ROOT);

        vm.startPrank(ADMIN);
        membership.grantRole(membership.TREASURY_ROLE(), ADMIN);
        vm.stopPrank();

        handler = new V5Handler(membership, usdt, ADMIN, ADMIN);
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = V5Handler.credit.selector;
        selectors[1] = V5Handler.fundReserve.selector;
        selectors[2] = V5Handler.withdrawReserve.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// A) Contract balance == pending award reserve. Entry credits are always
    ///    pushed out in the same tx; nothing stays behind by accident.
    function invariant_A_ContractBalanceMirrorsPendingReserve() public view {
        assertEq(
            usdt.balanceOf(address(membership)),
            membership.pendingTreasury(),
            "contract retained USDT beyond pending award reserve"
        );
    }

    /// B) Every credited wei is in treasury + company wallets. External award
    ///    reserve (`fundTreasury`) does NOT contribute here — it lives in the
    ///    contract until a withdrawal, at which point it splits and shows up.
    function invariant_B_CreditsFullyReachedWallets() public view {
        uint256 walletTotal = usdt.balanceOf(TREASURY) + usdt.balanceOf(COMPANY);
        uint256 credited = handler.ghostCreditedTotal();
        uint256 withdrawn = handler.ghostWithdrawnTotal();
        // The wallets accumulate both immediate credits AND withdrawn
        // reserves (which are also split 50/50 by V4's `withdrawTreasury`).
        assertEq(
            walletTotal,
            credited + withdrawn,
            "wallets don't equal credited + withdrawn"
        );
    }

    /// C) Odd-remainder rule: treasury >= company at all times, and the gap
    ///    is bounded by the number of split operations that could have
    ///    produced an odd remainder.
    function invariant_C_WalletGapWithinRoundingBudget() public view {
        uint256 tBal = usdt.balanceOf(TREASURY);
        uint256 cBal = usdt.balanceOf(COMPANY);
        assertGe(tBal, cBal, "company beat treasury");
        uint256 gapBudget = handler.creditCallCount() + handler.withdrawCallCount();
        assertLe(tBal - cBal, gapBudget, "wallet gap exceeded rounding budget");
    }

    /// D) `totalTreasuryPaid` accounts for every wei the treasury path
    ///    processed — both entry credits and external fund deposits.
    function invariant_D_TotalTreasuryPaidMatchesFlow() public view {
        assertEq(
            membership.totalTreasuryPaid(),
            handler.ghostCreditedTotal() + handler.ghostFundedTotal(),
            "totalTreasuryPaid drifted from ghost accounting"
        );
    }
}
