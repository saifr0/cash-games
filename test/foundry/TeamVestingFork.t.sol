// SPDX-License-Identifier: MIT
pragma solidity 0.8.31;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TeamVesting} from "../../contracts/TeamVesting.sol";

/// @notice Fork tests for TeamVesting against the live game pool on Arbitrum One.
///
/// Pool rules enforced by TeamVesting:
///   deposit(amount)  → owner only, ONLY before cliff elapses
///   withdraw(amount) → owner only, ONLY after cliff elapses
///
/// Run:
///   forge test --match-contract TeamVestingForkTest -v
contract TeamVestingForkTest is Test {

    // ── Arbitrum One ───────────────────────────────────────────────────────────
    address constant POOL_ADDR = 0x5e11dD1057bbaf3215CF45c1476e634F52eb6f5F;
    address constant CASH_ADDR = 0xEb435353f3629340df75437AEA83C6C6455e43d6;

    TeamVesting vesting;
    IERC20      cash = IERC20(CASH_ADDR);

    address owner = makeAddr("owner");

    // Short durations for testing (matching deployTeamVesting.js values)
    uint256 constant CLIFF      = 10 * 60;          // 10 minutes cliff
    uint256 constant MONTH_DUR  = 1 * 3600;         // 1 hour per month
    uint256 constant ALLOCATION = 23_400_000e18;

    function setUp() public {
        vm.createSelectFork(vm.envString("URL_ARB"));

        // Fresh TeamVesting — token + pool wired in constructor
        vesting = new TeamVesting(owner, CASH_ADDR, POOL_ADDR, CLIFF, MONTH_DUR, ALLOCATION);

        // Fund with CASH tokens via storage deal
        deal(CASH_ADDR, address(vesting), ALLOCATION);
    }

    // ── sanity ─────────────────────────────────────────────────────────────────

    function test_fork_setUp_sanity() public view {
        console.log("vesting          :", address(vesting));
        console.log("vestingStart     :", vesting.vestingStart());
        console.log("block.timestamp  :", block.timestamp);
        console.log("CASH balance     :", cash.balanceOf(address(vesting)));
        console.log("pool             :", address(vesting.pool()));

        assertEq(address(vesting.token()), CASH_ADDR);
        assertEq(address(vesting.pool()),  POOL_ADDR);
        assertEq(cash.balanceOf(address(vesting)), ALLOCATION);
        assertLt(block.timestamp, vesting.vestingStart(), "must start before cliff");
    }

    // ── deposit: only before cliff ─────────────────────────────────────────────

    function test_fork_deposit_worksBeforeCliff() public {
        assertLt(block.timestamp, vesting.vestingStart(), "pre-cliff guard");

        uint256 amount    = 1_000_000e18;
        uint256 balBefore = cash.balanceOf(address(vesting));

        vm.prank(owner);
        vesting.deposit(amount);

        assertEq(cash.balanceOf(address(vesting)), balBefore - amount);
        console.log("Vesting balance after deposit:", cash.balanceOf(address(vesting)));
        console.log("Pool    balance after deposit:", cash.balanceOf(POOL_ADDR));
    }

    function test_fork_deposit_multipleBeforeCliff() public {
        uint256 chunk = 500_000e18;

        vm.startPrank(owner);
        vesting.deposit(chunk);
        vesting.deposit(chunk);
        vesting.deposit(chunk);
        vm.stopPrank();

        uint256 remaining = cash.balanceOf(address(vesting));
        assertEq(remaining, ALLOCATION - chunk * 3);
        console.log("Vesting balance after 3 deposits:", remaining);
    }

    function test_fork_deposit_revertsAfterCliff() public {
        vm.warp(vesting.vestingStart());

        vm.prank(owner);
        vm.expectRevert(TeamVesting.VestingAlreadyStarted.selector);
        vesting.deposit(1_000_000e18);
    }

    function test_fork_deposit_revertsWellAfterCliff() public {
        vm.warp(vesting.vestingStart() + 30 days);

        vm.prank(owner);
        vm.expectRevert(TeamVesting.VestingAlreadyStarted.selector);
        vesting.deposit(1_000_000e18);
    }

    function test_fork_deposit_revertsNonOwner() public {
        vm.expectRevert();
        vesting.deposit(1_000_000e18);
    }

    function test_fork_deposit_revertsZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert(TeamVesting.ZeroAmount.selector);
        vesting.deposit(0);
    }

    // ── withdraw: only after cliff ─────────────────────────────────────────────

    function test_fork_withdraw_revertsBeforeCliff() public {
        vm.prank(owner);
        vesting.deposit(1_000_000e18);

        assertLt(block.timestamp, vesting.vestingStart());

        vm.prank(owner);
        vm.expectRevert(TeamVesting.VestingNotStarted.selector);
        vesting.withdraw(1_000_000e18);
    }

    function test_fork_withdraw_revertsAtCliffMinus1Second() public {
        vm.prank(owner);
        vesting.deposit(1_000_000e18);

        vm.warp(vesting.vestingStart() - 1);

        vm.prank(owner);
        vm.expectRevert(TeamVesting.VestingNotStarted.selector);
        vesting.withdraw(1_000_000e18);
    }

    function test_fork_withdraw_unlocksExactlyAtCliff() public {
        uint256 amount = 1_000_000e18;
        vm.prank(owner);
        vesting.deposit(amount);

        vm.warp(vesting.vestingStart());

        vm.prank(owner);
        vesting.withdraw(amount); // must not revert
    }

    function test_fork_withdraw_worksAfterCliff() public {
        uint256 amount = 2_000_000e18;
        vm.prank(owner);
        vesting.deposit(amount);

        vm.warp(vesting.vestingStart() + 7 days);

        vm.prank(owner);
        vesting.withdraw(amount); // must not revert
    }

    function test_fork_withdraw_revertsNonOwner() public {
        vm.warp(vesting.vestingStart() + 1);

        vm.expectRevert();
        vesting.withdraw(1_000_000e18);
    }

    // ── time-window symmetry ────────────────────────────────────────────────────

    function test_fork_boundary_lastSecondDeposit_firstSecondWithdraw() public {
        uint256 amount = 1_000_000e18;

        vm.warp(vesting.vestingStart() - 1);
        vm.prank(owner);
        vesting.deposit(amount); // must succeed

        vm.warp(vesting.vestingStart());
        vm.prank(owner);
        vesting.withdraw(amount); // must succeed
    }

    function test_fork_boundary_depositBlockedAtCliffStart() public {
        vm.warp(vesting.vestingStart());

        vm.prank(owner);
        vm.expectRevert(TeamVesting.VestingAlreadyStarted.selector);
        vesting.deposit(1_000_000e18);
    }

    function test_fork_boundary_withdrawBlockedBeforeCliffStart() public {
        vm.prank(owner);
        vesting.deposit(1_000_000e18);

        vm.warp(vesting.vestingStart() - 1);

        vm.prank(owner);
        vm.expectRevert(TeamVesting.VestingNotStarted.selector);
        vesting.withdraw(1_000_000e18);
    }

    // ── full lifecycle ─────────────────────────────────────────────────────────

    function test_fork_fullLifecycle() public {
        uint256 depositAmount = 5_000_000e18;

        // 1. Deposit before cliff
        assertLt(block.timestamp, vesting.vestingStart());
        vm.prank(owner);
        vesting.deposit(depositAmount);
        console.log("(1) After deposit - vesting:", cash.balanceOf(address(vesting)));
        console.log("(1) After deposit - pool   :", cash.balanceOf(POOL_ADDR));

        // 2. Withdraw attempt blocked before cliff
        vm.prank(owner);
        vm.expectRevert(TeamVesting.VestingNotStarted.selector);
        vesting.withdraw(depositAmount);

        // 3. Cliff elapses
        vm.warp(vesting.vestingStart() + 1);

        // Deposit now blocked
        vm.prank(owner);
        vm.expectRevert(TeamVesting.VestingAlreadyStarted.selector);
        vesting.deposit(1e18);

        // 4. Withdraw unlocked
        vm.prank(owner);
        vesting.withdraw(depositAmount); // must not revert
        console.log("(4) After withdraw - pool:", cash.balanceOf(POOL_ADDR));

        // 5. One month later — owner claims
        vm.warp(vesting.vestingStart() + MONTH_DUR);
        uint256 claimable = vesting.claimable();
        assertGt(claimable, 0);

        uint256 balBefore = cash.balanceOf(owner);
        vm.prank(owner);
        vesting.claim();
        console.log("(5) Owner received:", cash.balanceOf(owner) - balBefore);
    }
}
