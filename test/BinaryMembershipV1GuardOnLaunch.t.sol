// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {BinaryMembershipV1} from "../src/BinaryMembershipV1.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Checks the launch recommendation "enable `cycleGuardEnabled`
///         immediately after deployment" is actually safe to follow.
///
///  The guard was the source of a real defect once already: the placement
///  finder did no liveness check while the guard did, so with the guard on,
///  36 of 40 sponsors were handed slots that `register` rejected. That is
///  fixed, but a launch instruction is worth verifying rather than trusting,
///  because turning it on is the very first thing an operator would do.
contract BinaryMembershipV1GuardOnLaunchTest is Test {
    BinaryMembershipV1 internal guardOn;
    BinaryMembershipV1 internal guardOff;
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

    function _deploy(bool enableGuard) internal returns (BinaryMembershipV1 m) {
        vm.startPrank(ADMIN);
        m = new BinaryMembershipV1(IERC20(address(token)), TREASURY, ADMIN, 0, ROOT);
        m.grantRole(m.OPERATOR_ROLE(), OPERATOR);
        m.grantRole(m.TREASURY_ROLE(), TREASURY);
        m.configureStages(FEES, NODES, SLOTS, DEPTHS, AWARDS);
        if (enableGuard) m.setCycleGuardEnabled(true);
        vm.stopPrank();

        vm.prank(ROOT);
        m.register(address(0), address(0), BinaryMembershipV1.Side.None);
    }

    function setUp() public {
        token = new MockERC20("FAKEUSD", "FUSD", 0);

        token.mint(ROOT, 1_000_000 ether);
        for (uint256 i = 0; i < WALLETS; i++) {
            address u = address(uint160(0xC00000 + i));
            token.mint(u, 100_000 ether);
        }

        guardOn = _deploy(true);
        guardOff = _deploy(false);

        // Approvals for both deployments.
        vm.startPrank(ROOT);
        token.approve(address(guardOn), type(uint256).max);
        token.approve(address(guardOff), type(uint256).max);
        vm.stopPrank();
        for (uint256 i = 0; i < WALLETS; i++) {
            address u = address(uint160(0xC00000 + i));
            vm.startPrank(u);
            token.approve(address(guardOn), type(uint256).max);
            token.approve(address(guardOff), type(uint256).max);
            vm.stopPrank();
        }
    }

    function _user(uint256 i) internal pure returns (address) {
        return address(uint160(0xC00000 + i));
    }

    /// @dev Sponsor topology with concentrated recruiters, so boards overflow
    ///      and rollovers detach branches — the exact state the guard governs.
    function _sponsorOf(uint256 i) internal pure returns (address) {
        if (i < 3) return ROOT;
        return _user(i % 3);
    }

    /// @notice With the guard on, every placement the finder offers must still
    ///         be accepted, and the economics must match the guard-off run.
    function test_GuardOn_DoesNotBreakPlacementAtScale() public {
        uint256 gasOn;
        uint256 rejected;

        for (uint256 i = 0; i < WALLETS; i++) {
            address sponsor = _sponsorOf(i);
            (address p, BinaryMembershipV1.Side s) =
                guardOn.findPlacementSlot(sponsor, 0);
            assertTrue(p != address(0), "guard on: finder returned nothing");

            uint256 g0 = gasleft();
            vm.prank(_user(i));
            try guardOn.register(sponsor, p, s) {
                gasOn += g0 - gasleft();
            } catch {
                rejected++;
            }
        }

        assertEq(rejected, 0, "guard on rejected a slot its own finder offered");
        console.log("guard ON  - placements:", WALLETS, "rejected:", rejected);
        console.log("guard ON  - avg gas per join:", gasOn / WALLETS);
    }

    /// @notice Under normal bounded trees, enabling the guard is economically
    ///         neutral. Detached boards remain valid boundaries in both modes;
    ///         the guard only rejects actual cyclic/overdeep paths.
    function test_GuardOn_IsEconomicallyNeutralAndConserves() public {
        for (uint256 i = 0; i < WALLETS; i++) {
            address sponsor = _sponsorOf(i);

            (address p1, BinaryMembershipV1.Side s1) =
                guardOn.findPlacementSlot(sponsor, 0);
            vm.prank(_user(i));
            guardOn.register(sponsor, p1, s1);

            (address p2, BinaryMembershipV1.Side s2) =
                guardOff.findPlacementSlot(sponsor, 0);
            vm.prank(_user(i));
            guardOff.register(sponsor, p2, s2);
        }

        console.log("guard ON  pool:", guardOn.totalPoolPaid() / 1 ether);
        console.log("guard OFF pool:", guardOff.totalPoolPaid() / 1 ether);
        console.log("guard ON  treasury:", guardOn.pendingTreasury() / 1 ether);
        console.log("guard OFF treasury:", guardOff.pendingTreasury() / 1 ether);

        // Both modes must conserve every fee taken in.
        uint256 feesOn = guardOn.totalPoolPaid() + guardOn.pendingTreasury();
        uint256 feesOff = guardOff.totalPoolPaid() + guardOff.pendingTreasury();
        assertEq(feesOn, feesOff, "same members joined, so fees must match");
        assertEq(feesOn, WALLETS * FEES[0], "fees not conserved with guard on");

        assertEq(guardOn.totalPoolPaid(), guardOff.totalPoolPaid(), "guard changed member payouts");
        assertEq(guardOn.pendingTreasury(), guardOff.pendingTreasury(), "guard changed treasury");
    }

    /// @notice Gas cost of running with the guard on, under normal BFS shapes.
    ///         The guard walks up to MAX_LIVE_PATH links, so the question is
    ///         what it costs in practice, not at the adversarial ceiling.
    function test_GuardOn_GasOverheadIsAcceptable() public {
        uint256 gasOn;
        uint256 gasOff;

        for (uint256 i = 0; i < 300; i++) {
            address sponsor = _sponsorOf(i);

            (address p1, BinaryMembershipV1.Side s1) =
                guardOn.findPlacementSlot(sponsor, 0);
            uint256 a = gasleft();
            vm.prank(_user(i));
            guardOn.register(sponsor, p1, s1);
            gasOn += a - gasleft();

            (address p2, BinaryMembershipV1.Side s2) =
                guardOff.findPlacementSlot(sponsor, 0);
            uint256 b = gasleft();
            vm.prank(_user(i));
            guardOff.register(sponsor, p2, s2);
            gasOff += b - gasleft();
        }

        uint256 avgOn = gasOn / 300;
        uint256 avgOff = gasOff / 300;
        uint256 overheadPct = ((avgOn - avgOff) * 100) / avgOff;

        console.log("avg gas guard OFF:", avgOff);
        console.log("avg gas guard ON :", avgOn);
        console.log("overhead percent :", overheadPct);

        // Sanity ceiling: the guard must not double the cost of joining.
        assertLt(overheadPct, 100, "guard overhead is too high for launch");
    }
}
