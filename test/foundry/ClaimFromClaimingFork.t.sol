// SPDX-License-Identifier: MIT
pragma solidity 0.8.31;

import {Test, console} from "forge-std/Test.sol";
import {IERC20}        from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {TeamVesting} from "../../contracts/TeamVesting.sol";
import {Claiming}    from "../../contracts/Claiming/Claiming.sol";
import {Reservoir}   from "../../contracts/reservoir/Reservoir.sol";

/// @notice Fork test for TeamVesting.claimFromClaiming() against live contracts.
///
/// Flow under test:
///   1. Tokens are in the Reservoir (deposited at construction).
///   2. Cliff elapses.
///   3. owner → vesting.withdraw(amount)
///        Reservoir._withdraw routes tokens to Claiming and raises a request
///        for TeamVesting as the claimer.
///   4. Claiming cooldown elapses (1 minute, test value).
///   5. owner → vesting.claimFromClaiming(claiming, index)
///        TeamVesting calls claiming.claimRequest(index); tokens land back
///        in TeamVesting, ready for monthly claim().
///
/// Run:
///   forge test --match-contract ClaimFromClaimingForkTest -vvv
contract ClaimFromClaimingForkTest is Test {

    // ── Live contract addresses ───────────────────────────────────────────────
    address constant VESTING_ADDR = 0x72328044f55C1949E61aAc54449b627Dd5b58A0F;
    address constant OWNER        = 0x12eF0F1C99D8FD50fFd37cCd12B09Ef7f1213269;

    // ── Contract handles (resolved in setUp) ──────────────────────────────────
    TeamVesting vesting;
    IERC20      token;
    Reservoir   reservoir;
    Claiming    claiming;

    // ─────────────────────────────────────────────────────────────────────────
    // setUp
    // ─────────────────────────────────────────────────────────────────────────

    function setUp() public {
        vm.createSelectFork(vm.envString("URL_ARB"));

        vesting   = TeamVesting(VESTING_ADDR);
        token     = vesting.token();
        reservoir = Reservoir(address(vesting.pool()));
        claiming  = Claiming(reservoir.claiming());

        console.log("=== Live contracts ===");
        console.log("TeamVesting :", VESTING_ADDR);
        console.log("Token       :", address(token));
        console.log("Reservoir   :", address(reservoir));
        console.log("Claiming    :", address(claiming));
        console.log("vestingStart:", vesting.vestingStart());
        console.log("now         :", block.timestamp);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // test_claimFromClaiming
    // ─────────────────────────────────────────────────────────────────────────

    function test_claimFromClaiming() public {

        // ── 1. Sanity: TeamVesting holds shares in Reservoir ──────────────────
        uint256 shares = reservoir.balanceOf(token, VESTING_ADDR);
        console.log("\n[1] Shares in Reservoir :", shares);
        assertGt(shares, 0, "vesting has no shares - check constructor deposited correctly");

        // ── 2. Warp past cliff ────────────────────────────────────────────────
        vm.warp(vesting.vestingStart() + 1);
        console.log("[2] Warped past cliff to :", block.timestamp);

        // ── 3. Owner withdraws from pool → tokens route into Claiming ─────────
        uint256 withdrawable = reservoir.convertToAssets(token, shares);
        uint256 requestIndex = claiming.totalRequests(); // index our request will get
        console.log("[3] Withdrawable          :", withdrawable);
        console.log("    Request index          :", requestIndex);

        vm.prank(OWNER);
        vesting.withdraw(withdrawable);

        assertEq(
            token.balanceOf(address(claiming)),
            withdrawable,
            "Claiming should hold the withdrawn tokens"
        );
        assertEq(
            token.balanceOf(VESTING_ADDR),
            0,
            "TeamVesting should have no tokens while they sit in Claiming"
        );
        assertEq(
            claiming.totalRequests(),
            requestIndex + 1,
            "Exactly one new claim request should be pending"
        );
        console.log("    Claiming balance after withdraw :", token.balanceOf(address(claiming)));

        // ── 4. Warp past Claiming cooldown (1 minute in the live contract) ────
        vm.warp(block.timestamp + 2 minutes);
        console.log("[4] Warped past cooldown to :", block.timestamp);

        // ── 5. claimFromClaiming → tokens land back in TeamVesting ───────────
        uint256 balBefore = token.balanceOf(VESTING_ADDR);

        vm.prank(OWNER);
        vesting.claimFromClaiming(address(claiming), requestIndex);

        uint256 received = token.balanceOf(VESTING_ADDR) - balBefore;
        console.log("[5] TeamVesting received :", received);

        assertEq(
            received,
            withdrawable,
            "TeamVesting should receive the full withdrawn amount"
        );
        assertEq(
            token.balanceOf(address(claiming)),
            0,
            "Claiming should be empty after claimRequest"
        );

        console.log("\n=== claimFromClaiming OK - tokens back in TeamVesting ===");
        console.log("    TeamVesting balance :", token.balanceOf(VESTING_ADDR));
        console.log("    monthsClaimed       :", vesting.monthsClaimed());
        console.log("    claimable           :", vesting.claimable());
    }

    // ─────────────────────────────────────────────────────────────────────────
    // test_claimFromClaiming_revertsBeforeCooldown
    // ─────────────────────────────────────────────────────────────────────────

    function test_claimFromClaiming_revertsBeforeCooldown() public {
        // Warp past cliff, withdraw to create a request
        vm.warp(vesting.vestingStart() + 1);

        uint256 shares       = reservoir.balanceOf(token, VESTING_ADDR);
        uint256 withdrawable = reservoir.convertToAssets(token, shares);
        uint256 requestIndex = claiming.totalRequests();

        vm.prank(OWNER);
        vesting.withdraw(withdrawable);

        // Attempt claimFromClaiming immediately - cooldown not elapsed → revert
        vm.prank(OWNER);
        vm.expectRevert();
        vesting.claimFromClaiming(address(claiming), requestIndex);

        console.log("[OK] claimFromClaiming correctly reverts before cooldown");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // test_claimFromClaiming_revertsNonOwner
    // ─────────────────────────────────────────────────────────────────────────

    function test_claimFromClaiming_revertsNonOwner() public {
        vm.warp(vesting.vestingStart() + 1);

        uint256 shares       = reservoir.balanceOf(token, VESTING_ADDR);
        uint256 withdrawable = reservoir.convertToAssets(token, shares);
        uint256 requestIndex = claiming.totalRequests();

        vm.prank(OWNER);
        vesting.withdraw(withdrawable);

        vm.warp(block.timestamp + 2 minutes);

        // Non-owner call must revert
        vm.expectRevert();
        vesting.claimFromClaiming(address(claiming), requestIndex);

        console.log("[OK] claimFromClaiming correctly reverts for non-owner");
    }
}
