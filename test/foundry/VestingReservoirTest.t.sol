// SPDX-License-Identifier: MIT
pragma solidity 0.8.31;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {MockERC20}   from "../../contracts/MockERC20.sol";
import {Claiming}    from "../../contracts/Claiming/Claiming.sol";
import {Reservoir}   from "../../contracts/reservoir/Reservoir.sol";
import {TeamVesting} from "../../contracts/TeamVesting.sol";

contract VestingReservoirTest is Test {

    // Claiming cooldown is hardcoded to 2 minutes in the contract (test value).
    uint256 constant COOLDOWN   = 2 minutes;
    uint256 constant CLIFF      = 3 * 365 days;
    uint256 constant MONTH_DUR  = 30 days;
    uint256 constant ALLOCATION = 23_400_000e18;

    address owner = makeAddr("owner");

    MockERC20   cashToken;
    Claiming    claiming;
    Reservoir   reservoir;
    TeamVesting vesting;

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    function _fmt(uint256 wad) internal pure returns (string memory) {
        return string(abi.encodePacked(_itoa(wad / 1e18), " CASH"));
    }

    function _itoa(uint256 n) internal pure returns (string memory) {
        if (n == 0) return "0";
        uint256 tmp = n;
        uint256 len;
        while (tmp != 0) { len++; tmp /= 10; }
        bytes memory buf = new bytes(len);
        while (n != 0) { buf[--len] = bytes1(uint8(48 + n % 10)); n /= 10; }
        return string(buf);
    }

    function _sep() internal pure returns (string memory) {
        return "------------------------------------------------------------";
    }

    function _logBalances(string memory label) internal view {
        console.log("");
        console.log(label);
        console.log("  TeamVesting  :", _fmt(cashToken.balanceOf(address(vesting))));
        console.log("  Reservoir    :", _fmt(cashToken.balanceOf(address(reservoir))));
        console.log("  Claiming     :", _fmt(cashToken.balanceOf(address(claiming))));
        console.log("  Owner wallet :", _fmt(cashToken.balanceOf(owner)));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Setup
    // ─────────────────────────────────────────────────────────────────────────

    function setUp() public {
        console.log(_sep());
        console.log("SETUP");
        console.log(_sep());

        cashToken = new MockERC20("CashGames", "CASH", 18);
        console.log("  [1] CashGames token   :", address(cashToken));

        claiming = new Claiming(owner, IERC20(address(cashToken)));
        console.log("  [2] Claiming          :", address(claiming));

        Reservoir reservoirImpl = new Reservoir();
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(cashToken));
        bytes memory initData = abi.encodeCall(Reservoir.initialize, (assets, owner, address(claiming)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(reservoirImpl), initData);
        reservoir = Reservoir(address(proxy));
        console.log("  [3] Reservoir proxy   :", address(reservoir));

        vm.prank(owner);
        claiming.updateReservoir(address(reservoir));
        console.log("  [4] Reservoir wired into Claiming");

        vesting = new TeamVesting(owner, address(cashToken), address(reservoir), CLIFF, MONTH_DUR, ALLOCATION);
        console.log("  [5] TeamVesting       :", address(vesting));
        console.log("      cliff             : 3 years");
        console.log("      allocation        :", _fmt(ALLOCATION));

        cashToken.mint(address(vesting), ALLOCATION);
        console.log("  [6] Minted", _fmt(ALLOCATION), "to TeamVesting");

        _logBalances("  Initial balances");
        console.log(_sep());
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Full lifecycle
    // ─────────────────────────────────────────────────────────────────────────

    function test_fullLifecycle() public {

        // ── PRE-CHECKS ────────────────────────────────────────────────────────
        console.log("");
        console.log(_sep());
        console.log("PRE-CHECKS");
        console.log(_sep());
        assertEq(cashToken.balanceOf(address(vesting)),   ALLOCATION);
        assertEq(cashToken.balanceOf(address(reservoir)), 0);
        console.log("  [OK] TeamVesting holds full allocation");
        console.log("  [OK] Reservoir is empty");

        // ── STEP 1: DEPOSIT (before cliff) ────────────────────────────────────
        console.log("");
        console.log(_sep());
        console.log("STEP 1 -- Deposit all tokens into Reservoir (before cliff)");
        console.log(_sep());
        console.log("  vesting.deposit(", _fmt(ALLOCATION), ")");

        vm.prank(owner);
        vesting.deposit(ALLOCATION);

        uint256 shares = reservoir.balanceOf(IERC20(address(cashToken)), address(vesting));
        _logBalances("  Balances after deposit");
        console.log("  Shares minted to TeamVesting :", shares);

        assertEq(cashToken.balanceOf(address(vesting)),   0);
        assertEq(cashToken.balanceOf(address(reservoir)), ALLOCATION);
        assertGt(shares, 0);
        console.log("");
        console.log("  [OK] Tokens moved to Reservoir");
        console.log("  [OK] TeamVesting holds vault shares");

        // ── STEP 2: WARP 3 YEARS ──────────────────────────────────────────────
        console.log("");
        console.log(_sep());
        console.log("STEP 2 -- Warp +3 years (cliff elapses, withdraw window opens)");
        console.log(_sep());
        vm.warp(vesting.vestingStart() + 1);
        console.log("  block.timestamp :", block.timestamp);
        console.log("  vestingStart    :", vesting.vestingStart());
        console.log("  [OK] Cliff elapsed");

        // ── STEP 3: WITHDRAW from Reservoir ───────────────────────────────────
        console.log("");
        console.log(_sep());
        console.log("STEP 3 -- Withdraw from Reservoir (tokens route to Claiming)");
        console.log(_sep());

        uint256 withdrawable = reservoir.convertToAssets(IERC20(address(cashToken)), shares);
        console.log("  Withdrawable amount :", _fmt(withdrawable));
        console.log("  vesting.withdraw(", _fmt(withdrawable), ")");

        vm.prank(owner);
        vesting.withdraw(withdrawable);

        _logBalances("  Balances after withdraw");

        assertEq(cashToken.balanceOf(address(reservoir)), 0);
        assertEq(cashToken.balanceOf(address(claiming)),  withdrawable);
        assertEq(reservoir.balanceOf(IERC20(address(cashToken)), address(vesting)), 0);
        console.log("");
        console.log("  [OK] Reservoir empty, shares burned");
        console.log("  [OK] Claiming holds tokens with pending request for TeamVesting");

        // ── STEP 4: WARP past cooldown ────────────────────────────────────────
        console.log("");
        console.log(_sep());
        console.log("STEP 4 -- Warp past Claiming cooldown (2 minutes)");
        console.log(_sep());
        vm.warp(block.timestamp + COOLDOWN + 1);
        console.log("  block.timestamp :", block.timestamp);
        console.log("  [OK] Cooldown elapsed, claimRequest is now callable");

        // ── STEP 5: CLAIM FROM CLAIMING ───────────────────────────────────────
        console.log("");
        console.log(_sep());
        console.log("STEP 5 -- Pull tokens back into TeamVesting via claimFromClaiming");
        console.log(_sep());
        console.log("  vesting.claimFromClaiming(claiming, index=0)");
        console.log("  TeamVesting calls claiming.claimRequest(0)");
        console.log("  Tokens land in TeamVesting (claimer == TeamVesting)");

        vm.prank(owner);
        vesting.claimFromClaiming(address(claiming), 0);

        _logBalances("  Balances after claimFromClaiming");

        assertEq(cashToken.balanceOf(address(claiming)),     0);
        assertEq(cashToken.balanceOf(address(vesting)),      withdrawable);
        console.log("");
        console.log("  [OK] Claiming is empty");
        console.log("  [OK] TeamVesting holds tokens again, ready for monthly vesting");

        // ── STEP 6: CLAIM MONTH 1 ─────────────────────────────────────────────
        console.log("");
        console.log(_sep());
        console.log("STEP 6 -- Owner claims month-1 vesting tranche");
        console.log(_sep());

        vm.warp(vesting.vestingStart() + MONTH_DUR);
        uint256 claimable   = vesting.claimable();
        uint256 expected    = ALLOCATION / vesting.VESTING_MONTHS();
        console.log("  Claimable        :", _fmt(claimable));
        console.log("  Expected (1/24)  :", _fmt(expected));
        console.log("  vesting.claim()");

        vm.prank(owner);
        vesting.claim();

        _logBalances("  Balances after claim");

        assertEq(cashToken.balanceOf(owner), claimable);
        assertEq(vesting.monthsClaimed(), 1);
        console.log("");
        console.log("  [OK] Owner received month-1 tranche");
        console.log("  [OK] monthsClaimed == 1");

        // ── SUMMARY ───────────────────────────────────────────────────────────
        console.log("");
        console.log(_sep());
        console.log("SUMMARY");
        console.log(_sep());
        console.log("  1. Deposited into Reservoir   :", _fmt(ALLOCATION));
        console.log("  2. Withdrew to Claiming        :", _fmt(withdrawable));
        console.log("  3. Claimed back to TeamVesting :", _fmt(withdrawable));
        console.log("  4. Month-1 claimed to owner    :", _fmt(cashToken.balanceOf(owner)));
        console.log("  Remaining in TeamVesting       :", _fmt(cashToken.balanceOf(address(vesting))));
        console.log("  Months remaining               :", vesting.VESTING_MONTHS() - vesting.monthsClaimed());
        console.log(_sep());
    }
}
